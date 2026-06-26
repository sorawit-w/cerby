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
# don't match). GIT_GLOBAL_OPT matches option SHAPES, not a hardcoded list of
# names, so an unlisted or future flag before `commit` is still skipped. Two parts:
#   1. The FINITE set of value-taking globals (`git --help` synopsis) listed
#      explicitly with `[=[:space:]]` so BOTH `--opt=val` and `--opt val` (space)
#      forms consume their argument — the space form is otherwise ambiguous.
#   2. Shape fallbacks: any `--long=val`, any `--long` flag, any `-X` short flag.
GIT_GLOBAL_OPT='(-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+|--git-dir[=[:space:]][^[:space:]]+|--work-tree[=[:space:]][^[:space:]]+|--namespace[=[:space:]][^[:space:]]+|--super-prefix[=[:space:]][^[:space:]]+|--config-env[=[:space:]][^[:space:]]+|--exec-path[=[:space:]][^[:space:]]+|--attr-source[=[:space:]][^[:space:]]+|--[A-Za-z][A-Za-z-]*=[^[:space:]]+|--[A-Za-z][A-Za-z-]*|-[A-Za-z])'
GIT_COMMIT_RE="\\bgit\\b([[:space:]]+${GIT_GLOBAL_OPT})*[[:space:]]+commit\\b([[:space:]]|\$)"

if echo "$LC" | grep -qE "$GIT_COMMIT_RE"; then
  # Strip every override-AUTHORIZED commit invocation, then see if an UNauthorized
  # commit subcommand still remains. This makes the override per-invocation and
  # ties the assignment to the git it prefixes (not a token in an echo arg, a
  # commit message, or a different segment). sed on $CMD — the var is upper-case.
  STRIPPED=$(printf '%s' "$CMD" | sed -E 's/(^|[[:space:]])CODING_RULES_ALLOW_PROTECTED_COMMIT=1[[:space:]]+git[^|;&]*//g')
  STRIPPED_LC=$(printf '%s' "$STRIPPED" | tr '[:upper:]' '[:lower:]')
  if echo "$STRIPPED_LC" | grep -qE "$GIT_COMMIT_RE"; then
    # Resolve the branch each commit would ACTUALLY land on, then block on the
    # first protected one. Walk the command left-to-right by segment (split on
    # && || ; via bash expansion — portable; BSD sed makes literal-\n unreliable):
    #   - a `cd <path>` segment updates the effective directory for later BARE
    #     commits (`cd /repo && git commit`), replayed in a subshell with literal
    #     args — NEVER eval, so a path can't smuggle in a command.
    #   - a commit segment resolves its target: explicit --git-dir/-C on the
    #     invocation wins (git accepts globals in any order; a -C on a different
    #     sub-command must not leak in), else the accumulated cd chain, else cwd.
    # EVERY commit is checked, not just the first. Residual (a static pass can't
    # model these): pipes, subshells, `cd -`/`cd` home, relative cumulative
    # --git-dir, quoted separators/paths — see references/threat-model.md.
    CDLIST=""
    SEGTXT="$STRIPPED"
    SEGTXT="${SEGTXT//&&/$'\n'}"; SEGTXT="${SEGTXT//||/$'\n'}"; SEGTXT="${SEGTXT//;/$'\n'}"
    while IFS= read -r SEG; do
      # `cd <path>` (not `cd -` / bare `cd`) → remember for later bare commits
      if printf '%s' "$SEG" | grep -qE '^[[:space:]]*cd[[:space:]]+[^[:space:]-]'; then
        CDLIST="${CDLIST}$(printf '%s' "$SEG" | sed -E 's/^[[:space:]]*cd[[:space:]]+//; s/[[:space:]].*$//')
"
        continue
      fi
      printf '%s' "$SEG" | tr '[:upper:]' '[:lower:]' | grep -qE "$GIT_COMMIT_RE" || continue
      GITDIR=$(printf '%s' "$SEG" | grep -oE '(^|[[:space:]])--git-dir[=[:space:]][^[:space:]]+' | tail -1 | sed -E 's/.*--git-dir[=[:space:]]//')
      CPATH=$(printf '%s' "$SEG" | grep -oE '(^|[[:space:]])-C[[:space:]]+[^[:space:]]+' | tail -1 | sed -E 's/.*-C[[:space:]]+//')
      if [[ -n "$GITDIR" ]]; then LOC="--git-dir=$GITDIR"
      elif [[ -n "$CPATH" ]]; then LOC="-C $CPATH"
      else LOC=""; fi
      # Probe branch + HEAD in the effective location. Replay the cd chain in a
      # subshell (literal `cd` args); `git $LOC` is unquoted only for arg-splitting
      # — variable values are NOT re-tokenized, so `;`/`&` in a path stay literal.
      CURRENT=$(
        while IFS= read -r _d; do [ -n "$_d" ] && { cd "$_d" 2>/dev/null || exit 0; }; done <<< "$CDLIST"
        git $LOC branch --show-current 2>/dev/null
      )
      HAS_HEAD=$(
        while IFS= read -r _d; do [ -n "$_d" ] && { cd "$_d" 2>/dev/null || { echo 0; exit 0; }; }; done <<< "$CDLIST"
        git $LOC rev-parse --verify -q HEAD >/dev/null 2>&1 && echo 1 || echo 0
      )
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
    done <<< "$SEGTXT"
  fi
fi

exit 0
