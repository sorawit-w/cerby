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
# destructive blocks stay non-disablable). Use it inline, per-command
# (`CODING_RULES_ALLOW_PROTECTED_COMMIT=1 git commit …`), and only when the user
# has explicitly authorized committing to the protected branch.

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
# Unlike the checks above, this reads real repo state (the current branch), not
# just the command string. Carve-outs keep it quiet except on the actual mistake
# (committing onto main/develop/… mid-task instead of a feature branch).
# `\bcommit\b([[:space:]]|$)` matches `git commit` / `-m …` / `--amend` but NOT
# `git commit-graph` / `commit-tree` (the trailing `-` fails [[:space:]]|$).
if echo "$LC" | grep -qE '\bgit\b[^|;&]*\bcommit\b([[:space:]]|$)'; then
  # (a) explicit, auditable override → allow. (b) command creates/switches a
  # branch first (checkout -b / switch -c) → allow, since the commit lands there.
  if [[ "${CODING_RULES_ALLOW_PROTECTED_COMMIT:-}" != "1" ]] \
     && ! echo "$LC" | grep -qE '\bgit\b.*\b(checkout[[:space:]]+-b|switch[[:space:]]+-c)\b'; then
    CURRENT=$(git branch --show-current 2>/dev/null)
    # (c) allow when there's nothing to commit onto yet or no branch:
    #   - empty CURRENT = detached HEAD / not a repo
    #   - HEAD does not resolve = initial commit (unborn branch still reports a
    #     name via --show-current, so test HEAD separately)
    if [[ -n "$CURRENT" ]] && git rev-parse --verify -q HEAD >/dev/null 2>&1 \
       && echo "$CURRENT" | grep -qE "^${PROTECTED}$"; then
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
