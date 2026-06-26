#!/bin/bash
# Hook: Soft-warn if lint/test haven't been run before committing
# Type: PreToolUse on Bash matching git commit
# Name: pre-commit-check
# Exit 0 = allow action. The soft reminder is injected as JSON on STDOUT
# (hookSpecificOutput.additionalContext) — plain stdout on exit 0 is NOT surfaced
# to the agent for PreToolUse. The hard-block path uses exit 2 + stderr (which IS
# shown on the blocking path).
#
# This does NOT hard-block commits. It checks if lint/test commands
# were run recently in this session and reminds the agent if not.
# This avoids blocking on pre-existing lint errors from other developers.
#
# Disable the soft reminder with: CODING_RULES_HOOK_DISABLED=pre-commit-check
# The secret scan below cannot be disabled via env var — it is a
# security guardrail. To bypass, remove the hook from settings.json.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only check git commit commands
if ! echo "$COMMAND" | grep -qE '^git commit'; then
  exit 0
fi

# Secret scan on staged files.
# NOTE: This block is intentionally not gated by CODING_RULES_HOOK_DISABLED.
# Secret scanning is a hard security rule; disabling it requires editing
# settings.json, not setting an env var.
#
# Prefer gitleaks if present — broader coverage than the built-in regex, and it
# respects a repo-local .gitleaks.toml allowlist for example/test keys. Fall back
# to the narrow regex when gitleaks is absent OR errors. Critically, distinguish a
# gitleaks FINDING (exit 1 -> hard-block) from a TOOL ERROR (exit >=2 / 127 ->
# fall through to regex). A naive "nonzero -> block" would let a gitleaks config
# crash phantom-block every commit, and the block is non-disablable.
# (trufflehog is a viable alternative scanner; not wired here to keep one external
# integration and one test surface.)
# Pick a scanner by BINARY presence, not vendor (capability-gated). Prefer
# betterleaks (gitleaks' feature-frozen successor, same author) when installed,
# else gitleaks, else the built-in regex floor below.
SECRET_SCAN_DONE=""
SCANNER=""
if command -v betterleaks >/dev/null 2>&1; then
  SCANNER=betterleaks
elif command -v gitleaks >/dev/null 2>&1; then
  SCANNER=gitleaks
fi
if [[ -n "$SCANNER" ]]; then
  # Scan the staged diff's ADDED lines via `stdin` mode — the version-stable
  # invocation that survives gitleaks' 8.19 CLI reorg (which deprecated `protect`
  # in favor of `git`) and works the same on betterleaks. Added-only (-U0 + a
  # leading-'+' filter) is deliberate: scanning context or REMOVED lines would
  # block the very commit that refactors a secret OUT into env vars.
  # --exit-code 7 gives a DISTINCT leak code: the scanners' default exit 1 means
  # "leaks OR error", so a malformed config or any tool error would otherwise
  # phantom-block this NON-disablable hook. 7 = finding; any other nonzero = tool
  # error -> fall through to the regex (so an uncooperative scanner degrades, not
  # wedges). Output is suppressed: the scanner prints the matched secret, which we
  # must not echo into the agent's context.
  git diff --cached --diff-filter=ACMR -U0 2>/dev/null \
    | grep -E '^\+[^+]' \
    | "$SCANNER" stdin --no-banner --exit-code 7 >/dev/null 2>&1
  GL_RC=$?
  if [[ "$GL_RC" -eq 7 ]]; then
    echo "WARNING: $SCANNER detected possible secrets in staged changes." >&2
    echo "Output suppressed so the secret isn't echoed here — inspect locally with '$SCANNER stdin --redact', or allowlist a false positive in the scanner's config." >&2
    echo "See kerby security guardrails." >&2
    exit 2  # Hard-block on findings
  elif [[ "$GL_RC" -eq 0 ]]; then
    SECRET_SCAN_DONE=1  # scanner ran clean; trust it, skip the narrower regex
  else
    # Any non-7, non-0 code = tool error (bad config, unsupported flag, exec
    # failure), NOT a finding. Fall through to the regex floor.
    echo "NOTE (kerby): $SCANNER exited $GL_RC (tool error, not a finding); using built-in secret regex." >&2
  fi
fi

if [[ -z "$SECRET_SCAN_DONE" ]]; then
  SECRETS_FOUND=$(git diff --cached --diff-filter=ACMR -G '(sk_live_|sk_test_|AKIA[A-Z0-9]{16}|-----BEGIN (RSA |EC |DSA )?PRIVATE KEY-----|password\s*=\s*["\x27][^\s]+)' --name-only 2>/dev/null)
  if [[ -n "$SECRETS_FOUND" ]]; then
    echo "WARNING: Possible secrets detected in staged files:" >&2
    echo "$SECRETS_FOUND" >&2
    echo "Review these files before committing. See kerby security guardrails." >&2
    exit 2  # Hard-block on potential secrets
  fi
fi

# Respect the disable list for the soft reminder only.
case ",${CODING_RULES_HOOK_DISABLED:-}," in
  *,pre-commit-check,*) exit 0 ;;
esac

# Hollow-test heuristic (soft) — statically surface the "green run that proves
# nothing" fakes validation.md names: focused/disabled test markers and
# always-true assertions, in ADDED lines of staged test files only. Added-only
# means a teammate's pre-existing .skip never fires, and refactoring one OUT
# never trips it. Runtime fakes (0-match runs, gates over stubbed code) stay
# agent-judged — not statically detectable here. Soft like the reminder below:
# kerby reserves the hard block (exit 2) for secrets, not correctness. Reports
# COUNTS only — never echo raw test lines into the agent context. Pattern set is
# apostrophe-free (see the bash 3.2 note below) and word-anchored so fit(/xit(
# do not match the English word in a test description. Pathspecs are :(top)-
# anchored so a commit run from a subdirectory still scans staged test files
# repo-wide (a bare '*test*' is cwd-relative); .only/.skip permit a trailing dot
# so chained forms (test.only.each, describe.skip.each) are caught too.
HOLLOW_NOTE=""
TEST_ADDED=$(git diff --cached --diff-filter=ACMR -U0 -- ':(top)*test*' ':(top)*spec*' ':(top)*Test*' ':(top)*Spec*' 2>/dev/null | grep -E '^\+[^+]')
if [[ -n "$TEST_ADDED" ]]; then
  FOCUS=$(printf '%s\n' "$TEST_ADDED" | grep -cE '\.only[ (.]|\.skip[ (.]|\bfdescribe\(|\bfit\(|\bxit\(|\bxdescribe\(|@pytest\.mark\.skip|@(Disabled|Ignore)\b|\bt\.Skip\(')
  TRUE=$(printf '%s\n' "$TEST_ADDED" | grep -cE 'expect\( *true *\)\.(toBe\( *true *\)|toBeTruthy\()|assertTrue\( *[Tt]rue *\)|XCTAssertTrue\( *true *\)|assert\( *[Tt]rue *\)|assert +True\b')
  if [[ "$FOCUS" -gt 0 || "$TRUE" -gt 0 ]]; then
    HOLLOW_NOTE="
HOLLOW-TEST CHECK (kerby): staged test changes added $FOCUS focused/disabled marker(s) (only/skip/fit/xit) and $TRUE always-true assertion(s). A focused test silently disables the rest of the suite; an always-true assert verifies nothing — both yield a green run that proves nothing (validation.md Iron Law). Inspect your staged test/spec files and confirm each is intentional before committing. Advisory only; does NOT block."
  fi
fi

# Soft reminder — injected as context via JSON additionalContext (plain stdout on
# exit 0 is ignored for PreToolUse); does not block. NOTE: a PreToolUse
# additionalContext surfaces WITH the tool result (next turn), so this reminder
# arrives as the commit completes — it is a post-commit safety net, not a gate.
# The gate in this hook is the secret scan above (exit 2, pre-execution). Making
# this reminder gate the commit would mean permissionDecision ask/deny — a
# deliberate commit-discipline change, out of scope here.
# Plain double-quoted string (literal newlines), NOT a heredoc-in-$(...). Under
# bash 3.2 (macOS default) the command-substitution parser counts quotes even
# inside a quoted heredoc, so an ODD number of apostrophes in the body fails with
# "unexpected EOF while looking for matching '". Keeping this inline and
# apostrophe-free (like warn-env-read.sh) sidesteps it entirely.
REMINDER="REMINDER (kerby): verify your changes against the project gates —
1. lint on the changed files
2. the test suite
3. the build
This advisory surfaces WITH the commit result and does NOT block it; if your changes broke any gate, run it and amend the commit. Pre-existing failures from other code are acceptable — do not block on them.${HOLLOW_NOTE}"
jq -n --arg ctx "$REMINDER" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'

exit 0
