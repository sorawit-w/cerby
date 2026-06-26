#!/bin/bash
# Hook: Hard-block destructive git commands (data-loss guardrail)
# Type: PreToolUse on Bash
# Name: protect-git
# Exit 2 = block action, stderr shown to agent as feedback
#
# Blocks:
#   - git push --force / -f         (allows --force-with-lease)
#   - git push to a protected branch (main, master, dev, develop, staging, trunk, release/*)
#   - git reset --hard
#   - git clean -f / -fd / --force
#   - git branch -D / --delete --force
#   - git checkout . / git restore . / git checkout -- . (wholesale local discard)
#   - git commit while ON a protected branch (workflow guard — see below)
#
# Allows targeted variants: `git checkout -- src/foo.ts`, `git restore --staged file`,
# `git push origin feature/foo`, `git clean -n` (dry run), etc.
#
# The destructive blocks above are NOT disablable via CODING_RULES_HOOK_DISABLED.
# Data-loss-critical hooks cannot be toggled off by an env var.
# To bypass for a one-off, run the command yourself in a terminal.
# To remove permanently, delete the hook entry from .claude/settings.json
# (requires a deliberate file edit, not an ambient variable).
#
# EXCEPTION — the commit-on-protected-branch check (section 7) is a WORKFLOW
# guard, not a data-loss block, so it HAS a scoped escape hatch:
# `CODING_RULES_ALLOW_PROTECTED_COMMIT=1` bypasses ONLY that check (the
# destructive blocks stay non-disablable). Use it inline, per-command:
#   CODING_RULES_ALLOW_PROTECTED_COMMIT=1 git commit …
# and only when the user has explicitly authorized committing to the protected
# branch. The hook detects this assignment IN THE COMMAND STRING and only when it
# directly prefixes the `git commit` (it runs before the command, so it can't read
# the child shell's env). An ambiently-exported var, or the token appearing
# elsewhere in the command, is deliberately NOT honored — both are self-bypasses.

set -u

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [[ -z "$CMD" ]]; then
  exit 0
fi

# Lowercase for case-insensitive matching.
LC=$(echo "$CMD" | tr '[:upper:]' '[:lower:]')

block() {
  echo "BLOCKED: $1" >&2
  echo "Reason: destructive git command — data loss is hard or impossible to undo." >&2
  echo "If you really need this, run it yourself in a terminal." >&2
  echo "See kerby guardrails (hooks/protect-git.sh)." >&2
  exit 2
}

# 1. Force push (but allow --force-with-lease, which checks remote state first).
if echo "$LC" | grep -qE '\bgit\b.*\bpush\b.*(--force\b|[[:space:]]-f\b|[[:space:]]-[a-z]*f[a-z]*\b)'; then
  if ! echo "$LC" | grep -qE -- '--force-with-lease'; then
    block "git push --force / -f"
  fi
fi

# 2. Push to a protected branch. Matches BOOTSTRAP.md branching list.
PROTECTED='(main|master|dev|develop|staging|trunk|release/[^[:space:]]+)'
if echo "$LC" | grep -qE "\bgit\b.*\bpush\b[^|;&]*\b${PROTECTED}\b"; then
  block "git push to a protected branch"
fi

# 3. Reset --hard
if echo "$LC" | grep -qE '\bgit\b.*\breset\b.*--hard\b'; then
  block "git reset --hard"
fi

# 4. Clean with force flag.
if echo "$LC" | grep -qE '\bgit\b.*\bclean\b.*(-[a-z]*f[a-z]*\b|--force\b)'; then
  block "git clean -f / --force"
fi

# 5. Branch -D / --delete --force
if echo "$LC" | grep -qE '\bgit\b.*\bbranch\b.*(-d[a-z]*[[:space:]]|-[a-z]*d[a-z]*[[:space:]]|--delete[[:space:]]+--force\b)'; then
  # Match -D (capital D) explicitly, since lowercased above. After tr, -D becomes -d.
  # Distinguish -d (safe delete) from -D (force delete). After lowercasing both look the same,
  # so re-check the original CMD for capital -D.
  if echo "$CMD" | grep -qE '\bgit\b.*\bbranch\b.*-D\b'; then
    block "git branch -D"
  fi
  if echo "$LC" | grep -qE '\bgit\b.*\bbranch\b.*--delete[[:space:]]+--force\b'; then
    block "git branch --delete --force"
  fi
fi

# 6. Wholesale local discard: checkout . / restore . / checkout -- .
# Matches when the pathspec is exactly "." (the whole working dir).
# Allows targeted pathspecs like `git checkout -- src/foo.ts`.
if echo "$LC" | grep -qE '\bgit\b.*\b(checkout|restore)\b([[:space:]]+--)?[[:space:]]+\.([[:space:]]|$)'; then
  block "git checkout . / git restore . (wholesale local discard)"
fi

# 7. Commit while ON a protected branch (WORKFLOW guard — escapable, unlike 1–6).
# This reads real repo state (the TARGET repo's current branch), not just the
# command string, and it parses the git invocation rather than scanning for a bare
# "commit" word — so `git log --grep=commit` (subcommand `log`) is NOT a commit,
# while `git -C path commit` / `git -c k=v commit` are.
#
# A PreToolUse hook fires BEFORE the command runs, so:
#   - the inline override `VAR=1 git commit` lives in the child shell we can't see;
#     we parse the assignment out of the command string instead (never an exported
#     ambient var — that's a session-wide self-bypass), and per-invocation: an
#     override on a LATER commit must not authorize an earlier bare one.
#   - we cannot predict the runtime branch of a compound command (a `switch -c`
#     may fail, its new branch may be protected, `;` runs the commit regardless),
#     so branch creation and the commit must be SEPARATE commands — no carve-out.
#
# Subcommand matcher: `git`, zero or more global options (some take an arg), then
# `commit` as the subcommand (\b…([[:space:]]|$) so `commit-graph`/`commit-tree`
# don't match). Keep GIT_GLOBAL_OPT roughly in sync with `git --help` globals;
# an unknown global option before `commit` is a residual gap (see threat-model).
GIT_GLOBAL_OPT='(-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+|--git-dir[=[:space:]][^[:space:]]+|--work-tree[=[:space:]][^[:space:]]+|--namespace[=[:space:]][^[:space:]]+|-p|--paginate|--no-pager|--bare|--no-replace-objects|--literal-pathspecs|--icase-pathspecs|--no-optional-locks)'
GIT_COMMIT_RE="\\bgit\\b([[:space:]]+${GIT_GLOBAL_OPT})*[[:space:]]+commit\\b([[:space:]]|\$)"

if echo "$LC" | grep -qE "$GIT_COMMIT_RE"; then
  # Strip every override-AUTHORIZED commit invocation, then see if an UNauthorized
  # commit subcommand still remains. This makes the override per-invocation and
  # ties the assignment to the git it prefixes (not a token in an echo arg, a
  # commit message, or a different segment). sed on $CMD — the var is upper-case.
  STRIPPED=$(printf '%s' "$CMD" | sed -E 's/(^|[[:space:]])CODING_RULES_ALLOW_PROTECTED_COMMIT=1[[:space:]]+git[^|;&]*//g')
  STRIPPED_LC=$(printf '%s' "$STRIPPED" | tr '[:upper:]' '[:lower:]')
  if echo "$STRIPPED_LC" | grep -qE "$GIT_COMMIT_RE"; then
    # Probe the repo the commit actually targets: `git -C <path> commit` commits in
    # <path>, not the hook's cwd. Isolate the matched commit invocation first, then
    # take its `-C` — git accepts globals in any order, so `-C` may sit after other
    # globals (`git -c k=v -C /repo commit`), and a `-C` on a different sub-command
    # (`git -C /x status && git commit`) must NOT be used. Match in original case:
    # paths are case-sensitive and `-C` (chdir) ≠ `-c` (config). Last -C wins.
    # (Residual: multiple commit invocations with differing -C, quoted paths.)
    INVOC=$(printf '%s' "$STRIPPED" | grep -oE "$GIT_COMMIT_RE" | head -1)
    TARGET=$(printf '%s' "$INVOC" | grep -oE '(^|[[:space:]])-C[[:space:]]+[^[:space:]]+' | tail -1 | sed -E 's/.*-C[[:space:]]+//')
    if [[ -n "$TARGET" ]]; then
      CURRENT=$(git -C "$TARGET" branch --show-current 2>/dev/null)
      git -C "$TARGET" rev-parse --verify -q HEAD >/dev/null 2>&1 && HAS_HEAD=1 || HAS_HEAD=0
    else
      CURRENT=$(git branch --show-current 2>/dev/null)
      git rev-parse --verify -q HEAD >/dev/null 2>&1 && HAS_HEAD=1 || HAS_HEAD=0
    fi
    # Allow when there's nothing to commit onto yet or no branch:
    #   - empty CURRENT = detached HEAD / not a repo
    #   - HEAD does not resolve = initial commit (unborn branch still reports a name)
    if [[ -n "$CURRENT" && "$HAS_HEAD" == "1" ]] && echo "$CURRENT" | grep -qE "^${PROTECTED}$"; then
      echo "BLOCKED: git commit on protected branch '$CURRENT'." >&2
      echo "Create a feature branch first: git checkout -b feat/<short-description>" >&2
      echo "(or git switch -c fix/<...>), then stage and commit there." >&2
      echo "Workflow guard, not data loss. To commit here intentionally — and only" >&2
      echo "if the user authorized it — set the override inline for this command:" >&2
      echo "  CODING_RULES_ALLOW_PROTECTED_COMMIT=1 git commit ..." >&2
      echo "See kerby guardrails (hooks/protect-git.sh)." >&2
      exit 2
    fi
  fi
fi

exit 0
