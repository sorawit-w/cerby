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

# blocks: branch-create + commit in ONE command. A PreToolUse hook can't prove
# the commit lands off the protected branch (switch may fail, new branch may be
# protected, `;` runs commit regardless), so compound one-liners are NOT carved
# out — branch creation and commit must be separate commands.
R="$TMPROOT/on-main-branch-first"; repo_with_commit "$R" main
run_in "$R" "git switch -c feat/y && git commit -m x"
[[ "$RC" -eq 2 ]] && pass "blocks: switch -c && commit in one command (must split)" || fail "compound branch+commit must block (got $RC)"

# blocks: creating a protected branch then committing (release/* is protected)
R="$TMPROOT/on-main-rel"; repo_with_commit "$R" main
run_in "$R" "git switch -c release/1.0 && git commit -m x"
[[ "$RC" -eq 2 ]] && pass "blocks: switch -c release/1.0 && commit" || fail "protected new branch must block (got $RC)"

# blocks: commit comes BEFORE branch creation — commits to main first
R="$TMPROOT/on-main-commit-first"; repo_with_commit "$R" main
run_in "$R" "git commit -m x && git switch -c feat/y"
[[ "$RC" -eq 2 ]] && pass "blocks: commit-then-switch -c on main" || fail "commit-before-branch must block (got $RC)"

# blocks: override token as an arg in a different segment does NOT bypass
# (the assignment must directly prefix the git commit, not appear anywhere)
R="$TMPROOT/on-main-echo"; repo_with_commit "$R" main
run_in "$R" "echo CODING_RULES_ALLOW_PROTECTED_COMMIT=1 && git commit -m x"
[[ "$RC" -eq 2 ]] && pass "blocks: override token in another segment does not bypass" || fail "token-elsewhere must block (got $RC)"

# blocks: override token inside the commit message does NOT bypass
R="$TMPROOT/on-main-msgtoken"; repo_with_commit "$R" main
run_in "$R" "git commit -m 'CODING_RULES_ALLOW_PROTECTED_COMMIT=1'"
[[ "$RC" -eq 2 ]] && pass "blocks: override token in commit message does not bypass" || fail "token-in-message must block (got $RC)"

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

# allows: 'commit' as an ARGUMENT value, not the subcommand (no false-block)
R="$TMPROOT/grep-commit"; repo_with_commit "$R" main
run_in "$R" "git log --grep=commit"
[[ "$RC" -eq 0 ]] && pass "allows: git log --grep=commit on main (commit is an arg)" || fail "subcommand matcher false-blocked (got $RC)"

# blocks: a real commit subcommand behind a global option (-c k=v)
R="$TMPROOT/dash-c-opt"; repo_with_commit "$R" main
run_in "$R" "git -c user.name=x commit -m y"
[[ "$RC" -eq 2 ]] && pass "blocks: git -c user.name=x commit on main" || fail "global-opt commit must block (got $RC)"

# blocks: override on a LATER commit does not authorize an earlier bare one
R="$TMPROOT/multi-commit"; repo_with_commit "$R" main
run_in "$R" "git commit -m a && CODING_RULES_ALLOW_PROTECTED_COMMIT=1 git commit -m b"
[[ "$RC" -eq 2 ]] && pass "blocks: bare commit before an override-authorized commit" || fail "per-invocation override must block (got $RC)"

# -C target repo: the branch checked must be the TARGET repo's, not the hook cwd.
# cwd repo is on a feature branch; target repo is on main.
CWD_FEAT="$TMPROOT/cwd-feat"; repo_with_commit "$CWD_FEAT" feat/cwd
TGT_MAIN="$TMPROOT/tgt-main"; repo_with_commit "$TGT_MAIN" main
run_in "$CWD_FEAT" "git -C $TGT_MAIN commit -m x"
[[ "$RC" -eq 2 ]] && pass "blocks: git -C <repo-on-main> commit (probes target repo)" || fail "-C target branch must block (got $RC)"

# -C target repo on a feature branch → allowed even though cwd is also a feature
TGT_FEAT="$TMPROOT/tgt-feat"; repo_with_commit "$TGT_FEAT" feat/tgt
run_in "$CWD_FEAT" "git -C $TGT_FEAT commit -m x"
[[ "$RC" -eq 0 ]] && pass "allows: git -C <repo-on-feature> commit" || fail "-C feature target must allow (got $RC)"

# -C after another global option must still resolve to the target repo (P1):
# git accepts globals in any order, so -C may follow -c / --no-pager.
run_in "$CWD_FEAT" "git -c user.name=x -C $TGT_MAIN commit -m y"
[[ "$RC" -eq 2 ]] && pass "blocks: git -c k=v -C <repo-on-main> commit" || fail "-C after -c must block (got $RC)"
run_in "$CWD_FEAT" "git --no-pager -C $TGT_MAIN commit -m y"
[[ "$RC" -eq 2 ]] && pass "blocks: git --no-pager -C <repo-on-main> commit" || fail "-C after --no-pager must block (got $RC)"

# a -C on a NON-commit sub-command must not be used for the commit's branch check:
# the bare `git commit` here targets cwd (feat/cwd), so it is allowed.
run_in "$CWD_FEAT" "git -C $TGT_MAIN status && git commit -m x"
[[ "$RC" -eq 0 ]] && pass "allows: -C on a non-commit sub-command not used for commit" || fail "cross-invocation -C must not block (got $RC)"

# globals matched by SHAPE, not a name list: an unlisted short flag (-P) or long
# option (--config-env=...) before commit must still be detected as a commit.
R="$TMPROOT/dash-P"; repo_with_commit "$R" main
run_in "$R" "git -P commit -m x"
[[ "$RC" -eq 2 ]] && pass "blocks: git -P commit on main (unlisted short global)" || fail "-P commit must block (got $RC)"

R="$TMPROOT/config-env"; repo_with_commit "$R" main
run_in "$R" "git --config-env=foo.bar=ENV commit -m x"
[[ "$RC" -eq 2 ]] && pass "blocks: git --config-env=... commit on main" || fail "--config-env commit must block (got $RC)"

# -P before -C must still resolve the -C target repo (not fall back to cwd)
run_in "$CWD_FEAT" "git -P -C $TGT_MAIN commit -m x"
[[ "$RC" -eq 2 ]] && pass "blocks: git -P -C <repo-on-main> commit" || fail "-P then -C target must block (got $RC)"

# value-taking global in SPACE-separated form must consume its value, so commit
# is still detected: `git --config-env foo.bar=FOO commit` on main.
R="$TMPROOT/config-env-space"; repo_with_commit "$R" main
run_in "$R" "git --config-env foo.bar=FOO commit -m x"
[[ "$RC" -eq 2 ]] && pass "blocks: git --config-env <val> commit (space form)" || fail "--config-env space form must block (got $RC)"

# --git-dir/--work-tree name the target repo: branch must be probed there, not cwd.
# cwd is on a feature branch; the --git-dir repo is on main.
run_in "$CWD_FEAT" "git --git-dir=$TGT_MAIN/.git --work-tree=$TGT_MAIN commit -m x"
[[ "$RC" -eq 2 ]] && pass "blocks: git --git-dir=<repo-on-main> commit" || fail "--git-dir target must block (got $RC)"

# --git-dir pointing at a feature-branch repo → allowed
run_in "$CWD_FEAT" "git --git-dir=$TGT_FEAT/.git --work-tree=$TGT_FEAT commit -m x"
[[ "$RC" -eq 0 ]] && pass "allows: git --git-dir=<repo-on-feature> commit" || fail "--git-dir feature target must allow (got $RC)"

# EVERY commit invocation is checked, not just the first: first targets the
# feature cwd (allowed), second targets a protected repo via -C → must block.
run_in "$CWD_FEAT" "git commit -m a; git -C $TGT_MAIN commit -m b"
[[ "$RC" -eq 2 ]] && pass "blocks: later -C commit to protected repo after an allowed one" || fail "every commit must be checked (got $RC)"

# both commits target allowed (feature) repos → allowed
run_in "$CWD_FEAT" "git commit -m a; git -C $TGT_FEAT commit -m b"
[[ "$RC" -eq 0 ]] && pass "allows: multiple commits all on feature repos" || fail "all-feature multi-commit must allow (got $RC)"

# a leading `cd <repo>` changes where a BARE commit lands; honor it. cwd is on a
# feature branch; cd into a repo on main, then a bare commit → must block.
run_in "$CWD_FEAT" "cd $TGT_MAIN && git commit -m x"
[[ "$RC" -eq 2 ]] && pass "blocks: cd <repo-on-main> && git commit" || fail "cd then bare commit must block (got $RC)"

# cd into a feature-branch repo then commit → allowed
run_in "$CWD_FEAT" "cd $TGT_FEAT && git commit -m x"
[[ "$RC" -eq 0 ]] && pass "allows: cd <repo-on-feature> && git commit" || fail "cd to feature then commit must allow (got $RC)"

# cd with a semicolon separator is also honored
run_in "$CWD_FEAT" "cd $TGT_MAIN ; git commit -m x"
[[ "$RC" -eq 2 ]] && pass "blocks: cd <repo-on-main> ; git commit" || fail "cd ; commit must block (got $RC)"

echo "---"
if [[ "$FAILS" -eq 0 ]]; then
  echo "All assertions passed."
  exit 0
else
  echo "$FAILS assertion(s) failed."
  exit 1
fi
