#!/bin/bash
# Self-test for protect-git.sh — verifies destructive git commands are blocked
# (exit 2) and that legitimate / targeted variants are allowed (exit 0).
#
# Run from anywhere: bash protect-git.test.sh
# Exit 0 = all assertions pass; non-zero = a failure.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
HOOK="$SCRIPT_DIR/protect-git.sh"

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

run() { # $1 = command string -> sets RC
  printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -R .)" | bash "$HOOK" >/dev/null 2>&1
  RC=$?
}

# --- Must BLOCK (exit 2) -----------------------------------------------------
BLOCK=(
  "git push --force origin feature/x"
  "git push -f origin feature/x"
  "git push origin main"
  "git push origin master"
  "git push origin develop"
  "git reset --hard HEAD~1"
  "git clean -fd"
  "git clean --force"
  "git branch -D oldfeature"
  "git checkout ."
  "git restore ."
  "git checkout -- ."
)
for cmd in "${BLOCK[@]}"; do
  run "$cmd"
  [[ "$RC" -eq 2 ]] && pass "blocks: $cmd" || fail "should block (got $RC): $cmd"
done

# --- Must ALLOW (exit 0) -----------------------------------------------------
ALLOW=(
  "git push --force-with-lease origin feature/x"
  "git push origin feature/foo"
  "git checkout -- src/foo.ts"
  "git restore --staged src/foo.ts"
  "git clean -n"
  "git branch -d oldfeature"
  "git status"
)
for cmd in "${ALLOW[@]}"; do
  run "$cmd"
  [[ "$RC" -eq 0 ]] && pass "allows: $cmd" || fail "should allow (got $RC): $cmd"
done

# Empty command -> exit 0.
printf '{"tool_input":{"command":""}}' | bash "$HOOK" >/dev/null 2>&1
[[ "$?" -eq 0 ]] && pass "empty command exits 0" || fail "empty command should exit 0"

# --- Commit-on-protected-branch gate (needs real git state) ------------------
# The string-only harness above can't control the current branch; the commit
# gate reads `git branch --show-current`, so create real throwaway repos.
TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

repo_with_commit() { # $1 = dir, $2 = branch to end on
  git -c init.defaultBranch=main init -q "$1"
  git -C "$1" config user.email t@t.t
  git -C "$1" config user.name t
  echo x > "$1/f"
  git -C "$1" add -A
  git -C "$1" -c commit.gpgsign=false commit -qm init
  [[ "$2" != "main" ]] && git -C "$1" checkout -q -b "$2"
  return 0
}

run_in() { # $1 = dir, $2 = command -> sets RC
  printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$2" | jq -R .)" \
    | ( cd "$1" && bash "$HOOK" ) >/dev/null 2>&1
  RC=$?
}

# blocks: commit while on main
R="$TMPROOT/on-main"; repo_with_commit "$R" main
run_in "$R" "git commit -m x"
[[ "$RC" -eq 2 ]] && pass "blocks: git commit on main" || fail "should block commit on main (got $RC)"

# allows: commit on a feature branch
R="$TMPROOT/on-feat"; repo_with_commit "$R" feat/x
run_in "$R" "git commit -m x"
[[ "$RC" -eq 0 ]] && pass "allows: git commit on feat/x" || fail "should allow commit on feat/x (got $RC)"

# allows: commit on main with the scoped override — INLINE in the command, the
# only form a PreToolUse hook can actually see (it runs before the child shell).
R="$TMPROOT/on-main-override"; repo_with_commit "$R" main
run_in "$R" "CODING_RULES_ALLOW_PROTECTED_COMMIT=1 git commit -m x"
[[ "$RC" -eq 0 ]] && pass "allows: commit on main with inline override" || fail "inline override should allow (got $RC)"

# blocks: an AMBIENTLY-EXPORTED override does NOT bypass (no inline assignment in
# the command). This enforces the "inline only, never exported" scoping.
R="$TMPROOT/on-main-exported"; repo_with_commit "$R" main
export CODING_RULES_ALLOW_PROTECTED_COMMIT=1
run_in "$R" "git commit -m x"
unset CODING_RULES_ALLOW_PROTECTED_COMMIT
[[ "$RC" -eq 2 ]] && pass "blocks: exported (non-inline) override does not bypass" || fail "exported override must NOT bypass (got $RC)"

# allows: branch is created BEFORE the commit (carve-out b, correct order)
R="$TMPROOT/on-main-branch-first"; repo_with_commit "$R" main
run_in "$R" "git switch -c feat/y && git commit -m x"
[[ "$RC" -eq 0 ]] && pass "allows: switch -c then commit on main" || fail "branch-first compound should allow (got $RC)"

# blocks: commit comes BEFORE branch creation — commits to main first, must block
R="$TMPROOT/on-main-commit-first"; repo_with_commit "$R" main
run_in "$R" "git commit -m x && git switch -c feat/y"
[[ "$RC" -eq 2 ]] && pass "blocks: commit-then-switch -c on main" || fail "commit-before-branch must block (got $RC)"

# blocks: a commit whose message merely contains 'switch -c' is not carved out
R="$TMPROOT/on-main-msg"; repo_with_commit "$R" main
run_in "$R" "git commit -m 'try switch -c later'"
[[ "$RC" -eq 2 ]] && pass "blocks: 'switch -c' in commit message does not bypass" || fail "message red-herring must block (got $RC)"

# allows: initial commit, no HEAD yet, on main (carve-out c)
R="$TMPROOT/fresh"; git -c init.defaultBranch=main init -q "$R"
git -C "$R" config user.email t@t.t; git -C "$R" config user.name t
echo x > "$R/f"; git -C "$R" add -A
run_in "$R" "git commit -m init"
[[ "$RC" -eq 0 ]] && pass "allows: initial commit on fresh repo" || fail "initial commit should allow (got $RC)"

# allows: commit-graph maintenance on main (matcher precision, not a commit)
R="$TMPROOT/cg"; repo_with_commit "$R" main
run_in "$R" "git commit-graph write"
[[ "$RC" -eq 0 ]] && pass "allows: git commit-graph write on main" || fail "commit-graph should allow (got $RC)"

echo "---"
if [[ "$FAILS" -eq 0 ]]; then
  echo "All assertions passed."
  exit 0
else
  echo "$FAILS assertion(s) failed."
  exit 1
fi
