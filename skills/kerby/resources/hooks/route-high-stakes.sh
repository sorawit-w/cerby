#!/bin/bash
# Hook: Advise a full-workflow self-route when the agent EDITS a high-stakes path.
# Type: PreToolUse on Edit|Write matching BOOTSTRAP §3 high-stakes globs.
# Name: route-high-stakes
# Exit 0 always (never blocks). On a high-stakes match it emits a PreToolUse
# advisory as JSON on STDOUT (hookSpecificOutput.additionalContext) — the
# documented channel the agent reads on exit 0. Plain stderr on exit 0 is NOT
# surfaced to the model for PreToolUse, so this hook does not use stderr.
#
# This is the soft, behavioral counterpart that makes BOOTSTRAP §3's high-stakes
# path override [enforced-partial] instead of pure [behavioral]: an agent editing
# a one-line change inside `**/auth/**` (etc.) gets a reminder that this path
# requires feature.md / bugfix.md + the §4 Plan Gate, NOT quick-task. It never
# blocks — routing is a decision, not a destructive-action veto.
#
# GLOB SOURCE — canonical list is BOOTSTRAP §3 (resources/BOOTSTRAP.md, the
# "High-stakes path override" bullets). The GLOBS array below embeds those exact
# strings; route-high-stakes.test.sh asserts parity against §3 and FAILS if §3
# gains a glob this array doesn't carry. Keep the strings byte-identical to §3.
#
# COVERAGE GAP (documented, not a bug): §3's sixth category —
# production-traffic-shaping values (retry/timeout/rate-limit constants,
# feature-flag defaults, secrets-loading code) — is prose with no glob and CANNOT
# be path-matched. It stays [behavioral]. That named gap is what makes this rule
# [enforced-partial] rather than [enforced].
#
# Pattern absorbed (concept only, reimplemented) from
# paulDuvall/ai-development-patterns (MIT) — Progressive Disclosure. See NOTICE.
#
# Disable with: CODING_RULES_HOOK_DISABLED=route-high-stakes

# Respect the disable list (non-security soft hook).
case ",${CODING_RULES_HOOK_DISABLED:-}," in
  *,route-high-stakes,*) exit 0 ;;
esac

# High-stakes globs — byte-identical to BOOTSTRAP §3 (see GLOB SOURCE above).
GLOBS=(
  # Schema migrations
  '**/migrations/**' '**/prisma/migrations/**' '**/alembic/**' '**/db/migrate/**' '**/drizzle/**'
  # Authentication / authorization
  '**/auth/**' '*authz*' '*authentication*' '*login*' '*session*' '*token*'
  # Payments / billing
  '**/payments/**' '**/billing/**' '**/stripe/**' '**/checkout/**'
  # Infrastructure
  '**/*.tf' '**/*.tfvars' '**/terraform/**' '**/k8s/**' '**/kubernetes/**' '**/Dockerfile*' '**/docker-compose*.{yml,yaml}' '**/helm/**'
  # CI/CD
  '**/.github/workflows/**' '**/.gitlab-ci.{yml,yaml}' '**/Jenkinsfile' '**/.circleci/**' '**/buildkite/**'
)

# Translate one glob to an anchored ERE. ** spans directories; * stays within a
# segment; {a,b} -> (a|b); . is literal.
glob_to_regex() {
  local g="$1"
  g="${g//./\\.}"                  # .   -> \.
  g="${g//\{/(}"                   # {   -> (
  g="${g//\}/)}"                   # }   -> )
  g="${g//,/|}"                    # ,   -> |   (only ever appears inside braces here)
  g="${g//\*\*\//@@GLOBDIR@@}"     # **/ -> placeholder
  g="${g//\*\*/@@GLOB@@}"          # **  -> placeholder
  g="${g//\*/[^/]*}"               # *   -> [^/]*
  g="${g//@@GLOBDIR@@/(.*/)?}"     # **/ -> optional leading dirs
  g="${g//@@GLOB@@/.*}"            # **  -> any
  printf '%s' "$g"
}

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

base="$(basename "$FILE_PATH")"
matched=0
for g in "${GLOBS[@]}"; do
  re="$(glob_to_regex "$g")"
  # Path-globs (contain /) match the full path; filename-globs match the basename.
  if [[ "$g" == */* ]]; then target="$FILE_PATH"; else target="$base"; fi
  # Case-insensitive: §3's filename intent must catch Login.tsx / UserToken.ts, not just lowercase.
  if printf '%s' "$target" | grep -qiE "^${re}$"; then matched=1; break; fi
done

if [[ "$matched" -eq 1 ]]; then
  reminder="NOTE (kerby): $FILE_PATH is a high-stakes path (BOOTSTRAP §3 — auth/migrations/payments/infra/CI). This change requires workflows/feature.md or bugfix.md + the §4 Plan Gate, NOT quick-task — even for a one-liner. (Production-traffic-shaping paths aren't glob-matchable and stay your judgment call.)"
  # PreToolUse advisory: inject context as JSON on STDOUT — the documented channel
  # the agent actually reads on exit 0. Plain stderr on exit 0 is NOT surfaced to
  # the model for PreToolUse, so we do not use it. We deliberately emit ONLY
  # additionalContext — never permissionDecision — so the edit still goes through
  # normal permissions; this reminds, it must never auto-approve a high-stakes edit.
  jq -n --arg ctx "$reminder" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'
fi

exit 0
