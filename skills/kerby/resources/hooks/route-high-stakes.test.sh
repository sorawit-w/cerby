#!/bin/bash
# Self-test for route-high-stakes.sh — zero-framework, self-contained.
#
# Run from anywhere: bash route-high-stakes.test.sh
# Exit 0 = all assertions pass; non-zero = a failure.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
HOOK="$SCRIPT_DIR/route-high-stakes.sh"
BOOTSTRAP="$SCRIPT_DIR/../BOOTSTRAP.md"

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

run() { # $1=file path ; sets RC, OUT(stdout), CTX(additionalContext), DEC(permissionDecision)
  OUT=$(printf '{"tool_input":{"file_path":%s}}' "$(printf '%s' "$1" | jq -R .)" | bash "$HOOK" 2>/dev/null); RC=$?
  CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
  DEC=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
}

# --- One positive per globbable §3 category: additionalContext on stdout, exit 0 ---
POS=(
  "app/migrations/0001_init.sql"            # schema migrations
  "src/auth/login.ts"                       # authentication (dir glob)
  "src/UserToken.ts"                        # authentication (filename glob *token*)
  "services/payments/charge.go"             # payments
  "infra/main.tf"                           # infrastructure (extension glob)
  "Dockerfile"                              # infrastructure (root Dockerfile*)
  ".github/workflows/ci.yml"                # CI/CD
  "ci/Jenkinsfile"                          # CI/CD
)
for p in "${POS[@]}"; do
  run "$p"
  if [[ "$RC" -eq 0 ]] && printf '%s' "$CTX" | grep -q "high-stakes path"; then
    pass "high-stakes injects additionalContext: $p"
  else
    fail "should inject context (rc=$RC, ctx='$CTX'): $p"
  fi
done

# Advisory must NOT carry a permission decision — it reminds, never auto-approves.
run "src/auth/login.ts"
[[ -z "$DEC" ]] && pass "advisory sets no permissionDecision (no auto-approve)" \
  || fail "advisory must not set permissionDecision (got '$DEC')"

# A match must emit its reminder on stdout, not stderr (PreToolUse exit-0 channel).
STDERR=$(printf '{"tool_input":{"file_path":"src/auth/login.ts"}}' | bash "$HOOK" 2>&1 >/dev/null)
[[ -z "$STDERR" ]] && pass "match writes nothing to stderr (uses stdout JSON)" \
  || fail "match should not write to stderr (got '$STDERR')"

# --- Negatives: ordinary paths emit nothing, exit 0 --------------------------
NEG=(
  "src/util.ts"
  "README.md"
  "lib/helpers/format.js"
)
for p in "${NEG[@]}"; do
  run "$p"
  if [[ "$RC" -eq 0 && -z "$OUT" ]]; then
    pass "ordinary path silent (no JSON): $p"
  else
    fail "should be silent exit 0 (rc=$RC, out='$OUT'): $p"
  fi
done

# --- Missing path -> silent exit 0 -------------------------------------------
OUT=$(echo '{"tool_input":{}}' | bash "$HOOK" 2>/dev/null); RC=$?
[[ "$RC" -eq 0 && -z "$OUT" ]] && pass "missing path silent exit 0" \
  || fail "missing path should be silent (rc=$RC, out='$OUT')"

# --- Disabled via env var -> silent even on a high-stakes path ---------------
OUT=$(printf '{"tool_input":{"file_path":"src/auth/login.ts"}}' | CODING_RULES_HOOK_DISABLED=route-high-stakes bash "$HOOK" 2>/dev/null); RC=$?
[[ "$RC" -eq 0 && -z "$OUT" ]] && pass "disabled -> silent exit 0" \
  || fail "disabled should be silent (rc=$RC, out='$OUT')"

# --- Glob parity with BOOTSTRAP §3 (teeth-bearing) ---------------------------
# Extract the high-stakes override block, scope to its category bullets ('- **'),
# drop the prose production-traffic-shaping bullet (the documented [behavioral]
# gap — see the COVERAGE GAP note in route-high-stakes.sh), then assert every
# backticked token in the remaining bullets is embedded verbatim in the hook.
# No wildcard filter: a future non-wildcard §3 path (e.g. a bare `Dockerfile` or
# `.github/dependabot.yml`) must NOT silently slip the guard. This fails CLOSED —
# a stray backticked token in a category bullet demands explicit handling rather
# than a silent pass.
if [[ ! -f "$BOOTSTRAP" ]]; then
  fail "cannot find BOOTSTRAP.md at $BOOTSTRAP for parity check"
else
  BLOCK=$(sed -n '/High-stakes path override/,/blast radius/p' "$BOOTSTRAP")
  GLOBS_IN_SPEC=$(printf '%s\n' "$BLOCK" \
    | grep '^- \*\*' \
    | grep -vi 'traffic-shaping' \
    | grep -oE '`[^`]+`' | tr -d '`' | sort -u)
  if [[ -z "$GLOBS_IN_SPEC" ]]; then
    fail "parity: extracted zero globs from §3 — extraction is broken"
  fi
  # The prod-traffic-shaping category must contribute no required globs (it is the
  # named, un-globbable [behavioral] gap). If it ever sprouts a backticked token,
  # this guard's exclusion above keeps it out — assert the exclusion still holds.
  if printf '%s\n' "$BLOCK" | grep -i 'traffic-shaping' | grep -q '`'; then
    pass "parity: prod-traffic-shaping has backticks but is correctly excluded"
  else
    pass "parity: prod-traffic-shaping contributes no globs (prose-only)"
  fi
  # Parse the hook's ACTUAL GLOBS array (not arbitrary file text), so the guard
  # verifies the runtime list. A glob that survives only in a comment — while
  # being deleted from GLOBS — must NOT satisfy parity. Extract just the array
  # literal and eval it; this never runs the hook's stdin/jq logic.
  ARRAY_SRC=$(sed -n '/^GLOBS=(/,/^)/p' "$HOOK")
  if [[ -z "$ARRAY_SRC" ]]; then
    fail "parity: could not locate the GLOBS=( ... ) array in $HOOK"
  fi
  unset GLOBS; eval "$ARRAY_SRC"
  contains() { local x="$1"; shift; local e; for e in "$@"; do [[ "$e" == "$x" ]] && return 0; done; return 1; }
  MISSING=0
  while IFS= read -r g; do
    [[ -z "$g" ]] && continue
    if contains "$g" "${GLOBS[@]}"; then
      pass "parity: §3 glob in GLOBS array: $g"
    else
      fail "parity: §3 glob NOT in GLOBS array: $g"
      MISSING=$((MISSING + 1))
    fi
  done <<< "$GLOBS_IN_SPEC"
  [[ "$MISSING" -eq 0 ]] && pass "parity: all §3 globs present in the runtime GLOBS array"

  # Reverse direction — every runtime GLOBS entry must STILL exist in §3. Without
  # this, a glob removed or renamed in §3 but left in GLOBS keeps the hook firing
  # on paths BOOTSTRAP no longer treats as high-stakes, while parity still passes.
  # Forward + reverse = set equality. (The prose-only traffic-shaping gap lives in
  # §3 but never in GLOBS, so it doesn't affect this GLOBS⊆spec direction.)
  STALE=0
  for g in "${GLOBS[@]}"; do
    if printf '%s\n' "$GLOBS_IN_SPEC" | grep -qxF "$g"; then
      pass "parity: GLOBS entry present in §3: $g"
    else
      fail "parity: GLOBS entry NOT in §3 (stale/renamed?): $g"
      STALE=$((STALE + 1))
    fi
  done
  [[ "$STALE" -eq 0 ]] && pass "parity: no stale GLOBS entries (every runtime glob is in §3)"
fi

echo "---"
if [[ "$FAILS" -eq 0 ]]; then
  echo "All assertions passed."
  exit 0
else
  echo "$FAILS assertion(s) failed."
  exit 1
fi
