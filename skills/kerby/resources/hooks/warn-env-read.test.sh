#!/bin/bash
# Self-test for warn-env-read.sh — zero-framework, self-contained.
#
# Run from anywhere: bash warn-env-read.test.sh
# Exit 0 = all assertions pass; non-zero = a failure.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
HOOK="$SCRIPT_DIR/warn-env-read.sh"

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

run() { # $1=json input ; sets RC, OUT(stdout), CTX(additionalContext), DEC(permissionDecision)
  OUT=$(echo "$1" | bash "$HOOK" 2>/dev/null); RC=$?
  CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
  DEC=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
}

# 1. Read of a .env file -> exit 0 + reminder injected via stdout JSON additionalContext.
run '{"tool_input":{"file_path":"/proj/.env"}}'
[[ "$RC" -eq 0 ]] && pass ".env read exits 0" || fail ".env read should exit 0 (got $RC)"
printf '%s' "$CTX" | grep -q "never print its secret values" \
  && pass ".env read injects the secret-print warning via additionalContext" \
  || fail ".env read should inject the warning (ctx: '$CTX')"

# 1b. Advisory must NOT carry a permission decision (reading .env proceeds normally).
[[ -z "$DEC" ]] && pass ".env read sets no permissionDecision" \
  || fail ".env read must not set permissionDecision (got '$DEC')"

# 1c. The reminder must be on stdout, not stderr (PreToolUse exit-0 channel).
STDERR=$(echo '{"tool_input":{"file_path":"/proj/.env"}}' | bash "$HOOK" 2>&1 >/dev/null)
[[ -z "$STDERR" ]] && pass ".env read writes nothing to stderr (uses stdout JSON)" \
  || fail ".env read should not use stderr (got '$STDERR')"

# 2. Variant .env name (.env.local) also warns.
run '{"tool_input":{"file_path":".env.local"}}'
printf '%s' "$CTX" | grep -q "kerby" && pass ".env.local warns" || fail ".env.local should warn (ctx: '$CTX')"

# 3. Non-.env read -> exit 0, no JSON emitted.
run '{"tool_input":{"file_path":"src/app.ts"}}'
[[ "$RC" -eq 0 && -z "$OUT" ]] \
  && pass "non-.env read silent exit 0" \
  || fail "non-.env read should be silent exit 0 (rc=$RC, out='$OUT')"

# 4. Disabled via env var -> silent even for a .env read.
OUT=$(echo '{"tool_input":{"file_path":".env"}}' | CODING_RULES_HOOK_DISABLED=warn-env-read bash "$HOOK" 2>/dev/null); RC=$?
[[ "$RC" -eq 0 && -z "$OUT" ]] \
  && pass "disabled -> silent exit 0" \
  || fail "disabled should be silent (rc=$RC, out='$OUT')"

# 5. Empty/missing path -> exit 0, silent.
run '{"tool_input":{}}'
[[ "$RC" -eq 0 && -z "$OUT" ]] \
  && pass "missing path silent exit 0" \
  || fail "missing path should be silent exit 0 (rc=$RC, out='$OUT')"

echo "---"
if [[ "$FAILS" -eq 0 ]]; then
  echo "All assertions passed."
  exit 0
else
  echo "$FAILS assertion(s) failed."
  exit 1
fi
