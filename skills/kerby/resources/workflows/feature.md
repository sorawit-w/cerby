# Feature / Enhancement / Refactor Workflow

You are implementing a new feature, enhancement, or refactoring task. Follow these steps in order.

<pre_work>
## 1. Pre-Work

You MUST complete these before writing any code:

1. Read `references/working-patterns.md` — task approach, code standards
2. Read `references/communication.md` — commit format, logging, branch naming
3. Read project conventions — linter config, formatter config, existing code patterns
4. **Answer the Worktree Gate** (see BOOTSTRAP.md — 3 questions). If the gate → worktree, create it; else create an in-place branch.

   Worktree path (gate → yes):
   ```bash
   git worktree add .worktrees/<branch-name> -b <type>/<short-description>
   cd .worktrees/<branch-name>
   {package_manager} install    # bun install, pnpm install, etc.
   ```
   In-place path (gate → no, or npm fallback):
   ```bash
   git checkout -b <type>/<short-description>
   ```
   Ensure `.worktrees/` is in `.gitignore` before using worktrees. See `references/git-worktrees.md` for npm detection and fallback rules.
5. **Baseline check** — confirm you're starting from a clean state:
   - If you just created this worktree or in-place branch from a known-good base (main/develop passed CI): **skip baseline gates**
   - If `git status` shows a clean working tree and the last commit's gates passed: **skip baseline gates**
   - Otherwise, run full gates to establish baseline:
     ```bash
     {build_command} && {lint_command} && {test_command}
     ```
     If the baseline is broken, fix it first or flag it to the user.
</pre_work>

<clarify>
## 2. Clarify

If the request is ambiguous, ask 1–2 targeted questions. State your assumptions explicitly. Don't silently guess.

Check the knowledge base (`.ai/knowledge/`) for relevant decisions, conventions, or lessons that apply to this task. If the knowledge base answers a "why" question, use it instead of guessing or asking.

**Better-approach check (propose once, then defer).** If the user specified an approach, hasn't planned, and you see a *materially* better one for the *requested task*: surface it once — the option, why it's better, the cost of their choice, and a one-line "so you learn" note — in ≤3 lines. Then build what they asked unless they pivot. Do not relitigate after they choose; skip entirely for trivial tasks. This concerns the *requested task's* approach only — out-of-scope improvements stay logged-not-suggested (`BOOTSTRAP.md` §4 Guardrails).
</clarify>

<plan>
## 3. Plan

1. Restate the problem — confirm you understand what's being asked
2. Identify affected files — scope the change before editing
3. Check dependencies — will this change break anything downstream?
4. **If the feature introduces a new third-party vendor** (auth, db, payments, mailer, etc.), consult `references/vendor-adapters.md` for the ports/adapters pattern. Define the port from consumer needs; add the adapter under `adapters/<vendor>/`.
5. Rate complexity (1–10). **This table is the canonical complexity ladder — the single source of truth; other files point here.**

| Grade | Indicators | Approach |
|-------|-----------|----------|
| Low (1–3) | Single file, config, typo | Handle directly. Self-review when done. |
| Med (4–6) | Multiple related files, moderate logic | **Plan + Expected Outcomes** (below), then implement. Self-check when done. |
| High (7–8) | Multi-file, design decisions, new patterns | **Plan + Expected Outcomes, get user approval before starting.** QA sub-agent when done. |
| Critical (9–10) | Cross-cutting, architectural, breaking | Plan + approval + staged rollout. QA sub-agent when done. |

`plan_threshold` (`ai.planThreshold`, default 4) is the grade at/above which a written plan is required (`BOOTSTRAP.md` § 2.5 / § 4 Plan Gate). For complexity 6+, read `references/implementation-planning.md` for structured planning.

### Expected Outcomes (grade ≥ `plan_threshold`)

Before any code, predict the **observable end-state** — what the change will look like from outside, in the medium that fits. This is the prediction the finish step (§ 7) checks against. Predict the result, not the implementation.

| Change medium | Predict |
|---|---|
| UI | 2–3 line description or rough sketch of the surface + key states (empty / loading / error) |
| API | the request/response payload shape |
| CLI / script | the output lines the user will see |
| Data / state | the state transition (before → after) |

Below `plan_threshold` this block is optional.
</plan>

<delegate_check>
## 4. Check: Should You Delegate?

**Before implementing, check the delegation signals below.** If ANY signal matches, you MUST read `references/sub-agent-delegation.md` before deciding — then delegate, *unless* its overhead check says an inline pass is cheaper (a small, single-threaded task just over a threshold). The signals trigger the decision; they don't pre-make it.

| Signal | Match? |
|--------|--------|
| Task touches 3+ files | → Delegate |
| Task involves iterative debugging/fixing | → Delegate |
| Multiple independent sub-tasks exist | → Delegate in parallel |
| You catch yourself thinking "this should be quick" | → Delegate |
| Task estimated at >15 minutes of focused work | → Delegate |

If NO signals match (single-file change, trivial fix), proceed to implement yourself.

**If your agent platform does not support spawning sub-agents** (e.g., Cursor, Windsurf, Copilot), skip delegation and implement sequentially using the task loop below. The loop still applies — commit after each piece of work.

If you delegate, brief each sub-agent with: task + scope + files + done-when + constraints. Use quick briefs for complexity ≤5, full briefs for 6+. See `references/sub-agent-delegation.md` for templates.
</delegate_check>

<implement>
## 5. Implement — Task Loop

Whether you implement yourself or coordinate sub-agents, repeat this loop for each piece of work:

```
┌─→ 1. PICK   — Choose the next task or sub-task
│              If tracked in ROADMAP.md, flip [ ] → [~]
│   2. DO     — Implement (prefer TDD: failing test → minimal code → pass)
│   3. CHECK  — Iteration check (fast feedback):
│              Choose tier based on what you changed (see below)
│   4. COMMIT — Commit check (full gates) + commit:
│              {build_command} && {lint_command} && {test_command}
│              git add <specific-files>
│              git commit -m "<type>(<scope>): <description>"
│              If commit completes a ROADMAP feature, flip [~] → [x]
│              and sweep to ## Shipped (immediately or in batches)
│   5. LOG    — Append to .ai/memory.log (see BOOTSTRAP.md section 4 for format)
│   6. PUSH   — In multi-session work: git push
└─── 7. REPEAT — Go to step 1 for the next task
```

### Iteration Check Tiers (step 3)

Pick the tier that matches your change. See `references/quality-gates.md` for details.

| Changed... | Iteration check | Why |
|-----------|----------------|-----|
| Config, docs, comments, formatting only | `{lint_command}` | No logic changed — lint catches typos/format |
| Logic in 1–2 files | `{lint_command}` + related tests only | Fast feedback on what you just touched |
| 3+ files, cross-cutting, or dependency changes | Full: `{build_command} && {lint_command} && {test_command}` | Too risky to skip — run everything |

**"Related tests only"** = run the test file(s) that cover the module you changed. If unsure which tests are related, run the full suite.

### Commit Check (step 4)

**Always run full gates before committing — no exceptions.** The iteration check is for fast feedback during coding. The commit check is your safety net.

```bash
{build_command} && {lint_command} && {test_command}
```

If gates fail, fix the issue and re-run before committing.

**Rules for this loop:**
- Do NOT batch commits at the end. Each piece of completed work gets its own commit.
- Do NOT skip the commit check. Full gates must pass before every commit.
- If stuck after 3 attempts on one task, log what you tried, mark BLOCKED, move to the next task.
- If a ROADMAP item is blocked mid-loop, flip `[~]` → `[!]` with a one-line reason and continue. Resume by flipping back to `[~]` when the blocker clears.
- Match existing patterns in the codebase — consistency over local optimization.
- **Debug systematically** — reproduce → hypothesize (max 3) → fix. No trial-and-error. Details: `references/debugging.md`
- **Cheapen the loop before grinding** — if two fix-test cycles on one task have failed, stop before a third and reduce the cost of a single cycle (minimal reproduction, focused test command, or watch mode) instead of grinding through more attempts. A faster loop changes how many hypotheses you can afford. Why: `references/debugging.md` § feedback loop.
</implement>

<validate>
## 6. Validate

After all tasks in the loop are complete, perform final validation:

| Complexity | Validation |
|-----------|-----------|
| Low (1–3) | Self-review: run gates, re-read diff, confirm it does what was asked |
| Med (4–6) | Self-check: spec compliance check + run gates fresh |
| High (7+) | Spawn QA sub-agent for two-stage review: spec compliance then code quality |

- **If work was fanned out to parallel sub-agents**, run the integration gate before declaring done — see `references/sub-agent-delegation.md` rule 6 (cross-slice build + union of touched-module tests). Slice-local passes are not sufficient.

**No completion claims without fresh verification evidence.** Never say "should work" or "probably passes" — run the check, read the output, state the result.

Details: `references/validation.md`
</validate>

<finish>
## 7. Finish

Complete ALL of these before declaring done:

1. **Final quality gates pass:**
   ```bash
   {build_command} && {lint_command} && {test_command}
   ```
2. **All changes committed and pushed:**
   ```bash
   git status  # must show clean working tree
   git worktree list  # verify no other worktrees have uncommitted work
   ```
3. **Memory log updated** — session summary appended to `.ai/memory.log`
4. **STATUS.md updated** — `.ai/STATUS.md` reflects current state
5. **`ROADMAP.md` self-check** — completed features flipped to `[x]` and swept to `## Shipped`; new in-scope items added if scope expanded mid-task. The flips should already have happened in the COMMIT step of the loop; this is the verification
6. **Manual verification instructions provided** — tell the developer how to test:
   ```markdown
   ## How to Verify
   1. [Step-by-step instructions]
   2. [What to look for]
   3. [Edge cases to test]
   4. [Environment setup if needed]
   ```
7. **Realized Outcomes captured (grade ≥ `plan_threshold`)** — distinct from "How to Verify" above (that's instructions for the human; this is *your* check against the § 3 prediction). *Skip this step only when the plan was waived by a logged user opt-out (`BOOTSTRAP.md` § 2.5) — there is no Expected Outcome to compare against; standard Verification (§ 6) still applies.* After implementing:
   1. Capture the **actual** result from a real run — or a dry-run transcript where no runnable surface exists — and place it next to the § 3 Expected Outcome. Evidence is an object (screenshot path / captured JSON / CLI dump / diff), **not** prose.
   2. Emit `outcome: match | mismatch`.
   3. On `mismatch`, classify the cause and route — **only one branch changes code**:
      - **Code wrong** (real bug) → fix via the § 5 task loop, bounded by the existing circuit breaker (`references/working-patterns.md`: 3 no-progress / same error 3×; `references/error-handling.md`: build 5 / test 3 / lint 5 → BLOCKED). No new loop.
      - **Prediction wrong** (system is fine) → update the § 3 Expected Outcome with a one-line reason and log it to `.ai/memory.log` (recurring wrong predictions signal mis-calibrated planning). No code change.
      - **Ambiguous** → STOP. Surface both artifacts + your hypothesis. The human adjudicates.

   Realized evidence is recorded as-observed — never edited to match the prediction (`references/validation.md` Iron Law).
8. **DEVELOPER_TODO.md created** if any human actions are needed (API keys, cloud resources, etc.)
9. **Project knowledge artifacts** — propose additions before writing; skip if nothing applies:
   - **`.ai/knowledge/` entry** for a new decision, convention, or lesson
   - **`CONTEXT.md` update** for new domain terms used 2+ times. See `references/domain-glossary.md`.
10. **Branch finalization — pick one of four options** (ask the user if unclear):

   | Option | When to use | Action |
   |--------|-------------|--------|
   | **Open PR** (default) | Work is ready for human review | Push branch; open PR; keep worktree until PR is merged |
   | **Merge locally** | Solo project, fast-path, or approved | `git checkout <base>`, merge, then `git worktree remove .worktrees/<name>` |
   | **Preserve branch** | More work expected later | Keep worktree; note branch + reason in `.ai/memory.log` |
   | **Discard** | Work is a dead-end or spike | Requires explicit "discard" confirmation from user; then `git worktree remove --force .worktrees/<name>` |

   If using an in-place branch (npm fallback), skip worktree cleanup — only option 1 or 2 applies.

11. **Do NOT merge to a protected branch without explicit user instruction** — leave option 1 (PR) as the default.

Details: `references/context-management.md`, `references/git-worktrees.md`
</finish>
