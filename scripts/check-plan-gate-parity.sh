#!/bin/bash
# Parity: the Plan Gate constants must agree across EVERY file that restates them.
#
# Two constants are duplicated across shipped guidance (each file must stand
# alone): the plan_threshold DEFAULT (4) and the fixed APPROVAL point (grade >= 7).
# Nothing stops them drifting when one file is edited and the rest aren't — this
# does. CLAUDE.md tells authors to rely on this guard after changing either
# constant, so the checked set must include ALL restatements, not just two files.
# When a new restatement ships, add the file to the set below (or drop its literal).
#
# Mirrors the bidirectional glob-parity guard in hooks/route-high-stakes.test.sh:
# same teeth-bearing shape, so shipped guidance can't silently disagree.
#
# Run: bash scripts/check-plan-gate-parity.sh
# Exit 0 = constants agree everywhere and the cap invariant holds; non-zero =
# cross-file drift, within-file drift, a missing constant, or default > approval.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
RES="$SCRIPT_DIR/../skills/kerby/resources"

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

# Every file that restates the plan_threshold DEFAULT as a literal.
DEFAULT_FILES=(
  BOOTSTRAP.md
  workflows/feature.md
  workflows/quick-task.md
  references/working-patterns.md
  templates/agent-context.yaml.template
)
# Every file that restates the fixed grade>=7 APPROVAL point / cap. (The schema
# is the authoritative cap; implementation-planning.md's "complexity ≥ 7" is a
# roadmap-sizing reference, a different concept, deliberately excluded.)
APPROVAL_FILES=(
  BOOTSTRAP.md
  workflows/feature.md
  agent-context.schema.yaml
)

for rel in "${DEFAULT_FILES[@]}" "${APPROVAL_FILES[@]}"; do
  [[ -f "$RES/$rel" ]] || fail "cannot find $RES/$rel"
done
[[ "$FAILS" -eq 0 ]] || { echo "---"; echo "$FAILS assertion(s) failed."; exit 1; }

# Default plan_threshold: a "default <N>" on a line that NAMES the knob (so an
# unrelated "default 180 days" can't be mistaken for it), plus the YAML form
# `planThreshold: <N>`. Returns every DISTINCT value found, one per line.
extract_default() { # $1=file
  {
    grep -iE 'plan_?threshold' "$1" | grep -oE 'default \**[0-9]+' | grep -oE '[0-9]+'
    grep -oE 'planThreshold:[[:space:]]*[0-9]+' "$1" | grep -oE '[0-9]+'
  } | sort -u
}

# Fixed approval point: "grade ≥ N" (Unicode ≥ or ascii >=), "capped at N", or
# the schema's "maximum: N". Returns every DISTINCT value found, one per line.
extract_approval() { # $1=file
  grep -oE 'capped at [0-9]+|≥ ?[0-9]+|grade ?>= ?[0-9]+|maximum:[[:space:]]*[0-9]+' "$1" \
    | grep -oE '[0-9]+' | sort -u
}

# Check one constant across a SET of files: each file must state exactly ONE
# value (zero = the constant was dropped; >1 = a stale+updated pair drifting
# WITHIN the file), and all files must agree. Sets AGREED to the common value
# (empty on any failure) for the downstream invariant check.
check_constant() { # $1=label $2=extractor-fn $3.. = files (relative to RES)
  local label="$1" fn="$2"; shift 2
  local nfiles=$# rel raw n vals=""
  AGREED=""
  for rel in "$@"; do
    raw=$("$fn" "$RES/$rel")
    n=$(printf '%s\n' "$raw" | grep -c .)
    if   [[ "$n" -eq 0 ]]; then fail "$label: $rel states no value"; continue
    elif [[ "$n" -gt 1 ]]; then fail "$label: $rel drifts within file -> $(printf '%s' "$raw" | tr '\n' ',' | sed 's/,$//')"; continue
    fi
    pass "$label: $rel = $raw"
    vals="$vals$raw"$'\n'
  done
  local distinct; distinct=$(printf '%s' "$vals" | sort -u | grep -c .)
  if [[ "$distinct" -eq 1 ]]; then
    AGREED=$(printf '%s' "$vals" | sort -u | tr -d '\n')
    pass "$label: agrees across all $nfiles files ($AGREED)"
  else
    fail "$label: DRIFT across files -> $(printf '%s' "$vals" | sort -u | tr '\n' ',' | sed 's/,$//')"
  fi
}

check_constant "plan_threshold default" extract_default  "${DEFAULT_FILES[@]}";  DEFAULT_VAL="$AGREED"
check_constant "approval point"         extract_approval "${APPROVAL_FILES[@]}"; APPROVAL_VAL="$AGREED"

# Documented invariant: the default is "capped at" the approval point.
if [[ -n "$DEFAULT_VAL" && -n "$APPROVAL_VAL" ]]; then
  [[ "$DEFAULT_VAL" -le "$APPROVAL_VAL" ]] \
    && pass "invariant holds: default ($DEFAULT_VAL) <= approval ($APPROVAL_VAL)" \
    || fail "invariant broken: default ($DEFAULT_VAL) > approval ($APPROVAL_VAL)"
fi

echo "---"
if [[ "$FAILS" -eq 0 ]]; then
  echo "All assertions passed."
  exit 0
else
  echo "$FAILS assertion(s) failed."
  exit 1
fi
