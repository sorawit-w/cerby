# Validation Before Completion

**Iron Law: No completion claims without fresh verification evidence.**

Never say "done," "should work," "probably passes," or "seems correct." These words are red flags that you haven't verified. Run the verification, read the output, confirm it passes, *then* state the claim with evidence.

**Iron Law extension — outcome verification.** When a plan declared **Expected Outcomes**, the finish step captures **Realized Outcomes** from a real run — or a dry-run transcript where no runnable surface exists. Realized evidence is recorded as-observed and is **never edited to match the prediction**; a doctored result is the one failure this whole discipline exists to prevent. Judge `match` vs `mismatch` on **material intent** — does the behavior do what was predicted — not byte-exact comparison. Mismatch routing lives in `workflows/feature.md` § 7.

---

## The Verification Gate

Before declaring ANY task complete, regardless of complexity:

1. **Identify the verification command** — What proves this works? (test suite, build, manual check)
2. **Run it fresh** — Don't rely on cached results or earlier runs. Run it now.
3. **Read the full output** — Check exit code AND output content. A zero exit code with warning messages is not "passing."
4. **State the claim with evidence** — "Tests pass: 47 passed, 0 failed" not "tests should pass."

### Red Flag Phrases (Never Use These)

| Phrase | Why It's a Red Flag | Replace With |
|---|---|---|
| "Should work" | No evidence | "Tests pass: [output]" |
| "Probably passes" | Didn't run it | "Build succeeded: [output]" |
| "Seems correct" | Visual scan, no verification | "Verified by [specific check]" |
| "I believe this fixes it" | Hypothesis, not evidence | "Reproduced bug, applied fix, confirmed fix: [output]" |
| "Looks good" | Subjective | "Reviewed diff, ran quality gates: [results]" |

---

## What Counts as Evidence of Change

Verification produces *claims* about behavior — "the bug is fixed," "the perf regression is gone," "the race is closed." A claim without differential evidence is a guess. Three rules for what counts:

**Status codes / exit codes don't prove behavior.** A 200 response or a 0 exit code only proves the call completed — not that the *result* changed. Compare response bodies, output, file contents, or downstream state side-by-side before claiming a behavior change.

**Single observations are noise, not signal — especially for timing.** Perf claims, race-condition fixes, flaky-test stabilization, and any "this is faster / slower / now reliable" claim need repeated, interleaved trials before they're load-bearing. Use n≥10 as a floor; raise the floor when variance is high or stakes are large. A single fast/slow run is jitter, not evidence.

**A passing test is non-evidence if it's hollow or its target is a stub.** The Iron Law already forbids claiming done without evidence; this names the specific fakes that *look* like evidence. Before trusting green: always-true assertions (`expect(true).toBe(true)`), `.skip`/`.only`-narrowed tests, 0-match runs, and gates run over placeholder code (`TODO`, stubbed returns) are not passes. The `pre-commit-check` hook statically surfaces the first two — always-true assertions and focused/disabled markers (`.only`/`.skip`/`fit`/`xit`) — over your *added* test lines as a soft advisory; the runtime fakes (0-match runs, gates over stubs) are not statically detectable and stay agent-judged.

These apply to both the implementer and the QA sub-agent — a passing test suite the same run as the change is necessary but not sufficient for the three claim shapes above.

**Source:** absorbed from `elementalsouls/Claude-BugHunter` (2026-05-27); their bb-methodology PART 4 discipline gates (Body-Diff Rule, Statistical-Sample Rule) are security-framed, but the underlying engineering discipline applies broadly.
**Source (third rule):** absorbed from `shinpr/claude-code-workflows` (MIT, 2026-06-07); its `quality-fixer`/`task-executor` substance-check + stub-detection gate, generalized from that framework's CI orchestration into our verification pass.

---

## Verification by Complexity

Match verification depth to the risk of the work. Over-verifying simple tasks wastes time; under-verifying complex tasks causes regressions.

### Low Complexity (1–3): Self-Review

You verify your own work. No sub-agent needed.

1. Run quality gates (Standard tier — build + lint + test)
2. Re-read your own diff with fresh eyes
3. Confirm the change does what was requested
4. Provide verification evidence in your completion report

### Medium Complexity (4–6): Self-Check + Gates

You perform both verification stages yourself. No QA sub-agent — but you must be disciplined about separating the two checks:

**Check 1 — Spec Compliance** (before running gates):
> "Does this do what was asked?"
- Does the implementation satisfy the original request — not a drifted interpretation?
- Are all acceptance criteria met?
- Are edge cases from the requirements handled?
- Is anything missing that was explicitly requested?

**Check 2 — Quality Gates** (run fresh):
- Run Standard-tier gates: `{build_command} && {lint_command} && {test_command}`
- Re-read the diff for code smells:
  - Dead code (unused imports, orphans, unreachable branches)
  - **Hardcoded values** — externalize if the value (a) plausibly differs by environment (URLs, email destinations, default locales, retry budgets, timeouts) or (b) gates incomplete or risky work that may need to be turned off without redeploying. Untriggered values (enums, business-logic constants, validation thresholds) stay in code — speculative externalization is a smell of its own. Secrets remain governed by `guardrails.md` (`.env` only, never app config). For a value that stays in code but is *repeated* across ≥2 call sites, see **Hoist repeated literals to a single named source** in `working-patterns.md` § Code Standards — that's deduplication, a concern distinct from externalization.
  - **Shortcuts without an upgrade trigger** — a deliberate simplification (O(n²), in-memory, inline) whose adjacent comment doesn't name the measurable condition that should flip the decision. Add the trigger or remove the shortcut (see `working-patterns.md` § Code Standards).
  - Missing error handling
- Verify the change doesn't break adjacent functionality

Both checks must pass. If either surfaces issues, fix and re-verify.

### High/Critical Complexity (7+): Two-Stage QA Sub-Agent

Spawn a **separate QA sub-agent** that performs both stages independently. The sub-agent has fresh eyes and no implementation bias.

**Stage 1 — Spec Compliance:**
> "Does this do what was asked?"
- Same checks as medium complexity, but performed by a separate agent
- Catches the "wrong thing built well" failure mode

**Stage 2 — Code Quality:**
> "Is the code good?"
- Runs quality gates independently — don't trust the implementer's report
- Reviews the diff for missed edge cases, inconsistencies, and regressions
- Checks for code smells and verifies adjacent functionality isn't broken
- Catches the "right thing built badly" failure mode

**Both stages must pass** before the task is marked complete. If either stage surfaces issues, the implementing agent fixes them and the QA sub-agent re-verifies.

### Reviewing a past commit against the rules

The tiers above govern the change you are *making*. To review an **already-landed** commit (a teammate's, an agent's, or one made before these rules were adopted): `git show <sha>` (or `git diff <sha>~..<sha>`), then apply the same review lens used above — the Medium Check 2 code-quality pass plus the Security Lens below when it triggers. **The main agent runs this directly** — a past or foreign commit has no author-bias to insulate against, so the fresh-context QA sub-agent earns its cost only when the commit is large or complex enough to cross the **7+ complexity trigger** above. Don't invent a separate size threshold; reuse that one.

---

## Security Lens — Conditional Pass

A third lens that fires alongside the code-quality pass (Medium Check 2 or High Stage 2) when the diff touches security-sensitive surface. Don't fold it into every review — that's wasted attention. Run it explicitly when triggered.

**Triggers (any one fires the pass):**

- Auth / authz code (login, session, token handling, permission checks, role gates)
- Files holding or processing PII (user records, addresses, IDs, health, financial data)
- Payment paths (checkout, refunds, ledger entries, webhook handlers)
- Secrets handling (env loading, key rotation, vault access, credential parsing)
- Database migrations — especially destructive ones (DROP, ALTER constraint, schema rename)
- Public API surface changes without versioning
- File upload, deserialization, dynamic-code paths (`eval`, `exec`, shell invocation) — untrusted deserialization / unverified fetched code `[A08 · CWE-502/494]`
- Outbound requests to a URL or host influenced by user input — webhooks, link-preview / unfurlers, image/file fetchers, proxy endpoints; i.e. any outbound fetch whose destination a user can steer toward internal services or cloud metadata

**What the pass checks:**

- **Trust boundaries** — does untrusted input reach a sink without sanitization? `[A03 · CWE-20]`
- **Output encoding** — HTML / SQL / shell contexts use the right escape; no string concatenation into queries or commands `[A03 · CWE-79/89/78]`
- **Authn/authz placement** — is every protected endpoint actually protected, or did the new code create an unauthenticated path? `[A01 · CWE-862/285; auth failures A07 · CWE-287]`
- **Secret exposure** — no secrets in logs, error messages, response bodies, telemetry, commit history, or the agent's own chat output to the user `[A02 · CWE-200/532]`
- **Redaction** — when output must reference a secret, mask it (last-4 only); never reproduce a live credential verbatim, even when reading it back from a file the user showed you `[A02 · CWE-532]`
- **Timing-safe comparisons** where applicable (token comparison, signature verification) `[A02 · CWE-208]`
- **Crypto primitives** — using vetted libraries, not hand-rolled; modern algorithms (no MD5/SHA1 for security uses) `[A02 · CWE-327/916]`
- **Injection vectors** — SQL, command, LDAP, XPath, template, header, log injection `[A03 · CWE-89/78/90/643/94/113/117]`
- **SSRF** — a destination URL/host derived from user input is allowlisted, not raw-passed to an outbound request; internal ranges and cloud metadata (`169.254.169.254`) are blocked; no redirect-following or DNS-rebinding into internal targets `[A10 · CWE-918]`
- **Insecure design** — prefer secure-by-default patterns; threat-model the boundary before coding (see `working-patterns.md` § platform code, `safety-mindset.md`) `[A04 · CWE-657]`
- **Security misconfiguration** — safe defaults; no debug/verbose errors in prod; no permissive CORS; security headers set `[A05 · CWE-16]`
- **Indirect prompt injection** if the diff ingests agent-authored artifacts (see `guardrails.md` § Agent-Authored Artifacts as Untrusted Input) `[LLM01]`

**Standard targeted, not certified.** The bracketed tags map each check to the **OWASP Top 10 (2021)** (`Axx`) and — for `LLM01` — the **OWASP Top 10 for LLM Applications**; CWE IDs are indicative, not exhaustive. This lens is `[behavioral]`: it *targets* these standards best-effort by agent judgment, with nothing that mechanically verifies conformance. **Never describe code reviewed through it as "OWASP-compliant"** — the mapping is hand-maintained against the 2021 list and is not auto-tracked for drift.

**Do NOT skip when triggered.** Security failures from missed lenses are silent until exploited; the cost of running the pass is small relative to the cost of missing a vuln.

**Source:** absorbed from Claude Code's built-in `/security-review` slash command (2026-05-09); the methodology fits cleanly into the existing two-stage QA shape as a conditional third lens.

---

## Manual Verification Instructions

After completing an implementation, **always tell the developer how to manually verify it works** — emit the **How to Verify** block defined canonically in `BOOTSTRAP.md` § 4 (Manual Verification Instructions). Don't just say "done." This is especially important for UI changes, API behavior, and integrations where automated tests may not cover the full user experience.

### Give the agent a tool to *see* its output

Tests prove logic; they don't show the artifact. For visual, UI, or rendered output, wire a tool that lets the agent observe its own result — a browser/dev-server (e.g. a Playwright or preview MCP), a screenshot, or opening the rendered HTML — and tell the agent to use it. A loop where the agent sees what it built lets it self-correct before claiming done. Declare such tools in `agent-context.yaml`.
