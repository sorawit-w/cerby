# CLAUDE.md — the `kerby` repo

`kerby` is the gate guardian for agentic coding: a loadable rule-corpus + opt-in
guardrail hooks that govern how an agent does coding work (clarity over cleverness,
safety over speed, never leave the repo broken — and *nothing unproven passes the
gate*). The skill itself lives at [`skills/kerby/`](skills/kerby/SKILL.md); the rules
it loads live in [`skills/kerby/resources/BOOTSTRAP.md`](skills/kerby/resources/BOOTSTRAP.md).

This file is the repo-root context doc. Its main job is to hold the **harness-engineering
vocabulary** that `SKILL.md` references — the named primitives behind how `kerby` is
built. `kerby` is the canonical, working implementation of these primitives; when the
vocabulary below cites one abstractly, the concrete machinery is somewhere under
`skills/kerby/resources/`.

---

## Harness vocabulary

Building a rule-corpus like `kerby` is **harness engineering** — designing everything
*around* an agent that determines whether it succeeds: context, scaffolding, feedback,
state, evaluation. Naming the primitives lets edits be deliberate instead of accidental.

| Primitive | What it means | Concrete artifact in `kerby` |
|---|---|---|
| **Context engineering** | Organize information so the agent can reason over it — repo-local, versioned, not in chat threads. | `CONTEXT.md` (project glossary) + `BOOTSTRAP.md` (operating rules) + vendor agent-context files kept in sync — see `resources/references/multi-tool.md`. |
| **Progressive disclosure** | Load detail on demand instead of front-loading everything. | `BOOTSTRAP.md` is the index; `resources/references/*.md` carry the long-tail, loaded only when cited. |
| **Observable feedback loops** | Prefer machine-checkable signal over aspirational prose. | `resources/hooks/pre-commit-check.sh`, `protect-env.sh`, `warn-env-read.sh`, `protect-git.sh` + gates in `references/quality-gates.md` and `references/validation.md`. |
| **State preservation** | Carry useful context across session boundaries. | `.ai/memory.log` (append-only history) + `.ai/STATUS.md` (current state) + `.ai/knowledge/` (curated wiki) + `.ai/BLOCKERS.md`, bootstrapped by `session-start-context.sh` + `knowledge-bootstrap.sh`. |
| **Eval discipline** | Decide what "working" means before shipping. | `references/quality-gates.md` + the verification-before-completion pattern; the pre-commit hook enforces gates mechanically rather than relying on agent memory. |

**External reading:** Anthropic ([effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents), [harness design for long-running apps](https://www.anthropic.com/engineering/harness-design-long-running-apps)); OpenAI ([harness engineering](https://openai.com/index/harness-engineering/)); the [`AGENTS.md`](https://agents.md/) convention.

**How to use this vocabulary.** When you propose a new rule, ask: *which primitive is
this serving?* If you can't answer, the change is probably speculative. When you debug a
rule that "just isn't working," ask: *is the environment underspecified (context,
scaffolding, feedback) or is the prompt wrong?* Most agent failures are environment
failures wearing a prompt-failure mask.

### Control loop (loop engineering)

Prompt engineering optimizes a single forward pass. **Loop engineering** optimizes the
trajectory across many passes: the agent acts, observes a result (test output, build
error, screenshot), and that observation re-enters context and shapes the next action.
It is the runtime-control-flow half of harness engineering. `kerby` implements the loop
primitives; this table is the map — each row points to where the primitive is enforced.

| Primitive | One-line meaning | Lives in |
|---|---|---|
| Inner / outer check split | cheap check while coding, full gate at the boundary | `resources/workflows/feature.md` (iteration-check tiers vs commit check) |
| Termination condition | what must be true to exit the loop | `resources/references/validation.md` (Iron Law: no claim without fresh evidence) |
| Retry budget / circuit breaker | bounded retries per failure type, then escalate | `resources/references/error-handling.md` (build 5 / test 3 / lint 5 → BLOCKED) |
| Bounded search | cap the hypothesis count so the loop can't flail | `resources/references/debugging.md` (max 3 hypotheses) |
| State across iterations | what carries forward so the loop has no amnesia | `.ai/memory.log`, `.ai/STATUS.md`, checkpoint-before-context-fills |
| Iteration cost is the speed limit | a faster loop buys more hypotheses | `resources/references/debugging.md` (assess the feedback loop first) |
| Parallel loops (fan-out) | independent iterations run concurrently | `resources/references/sub-agent-delegation.md` (vertical slices, blind lenses) |

These are the runtime expression of the harness primitives above: *State across
iterations* is *State preservation* applied mid-task; the two check rows are *Observable
feedback loops* applied per-iteration. The rest (termination, retry budget, bounded
search, fan-out) are loop-specific.

**Bounded by design.** kerby's termination condition is deliberately *bounded*: the
loop exits on fresh verification evidence (the Iron Law) **or** on an exhausted
retry budget that escalates to a human (`BLOCKED`). It does **not** iterate
unboundedly toward "perfect." That bound is a choice, not an omission — *never leave
the repo broken* outranks autonomous self-correction, so a stuck loop hands off
rather than flails. This is the intended departure from naive "verify-until-done"
framings: a self-verification loop with no circuit breaker burns its budget
re-deriving the same wrong fix. The verification gate also leans behavioral by
design — the methodology travels across toolchains where a hardcoded check would not
(`skills/kerby/CLAUDE.md` § Authoring style). The one mechanical floor under it is
`resources/hooks/pre-commit-check.sh`: the non-disablable secret scan, plus a soft
hollow-test heuristic that statically flags the green-but-empty fakes
(`resources/references/validation.md` § What Counts as Evidence).

---

## Editing the rules

The skill-internal authoring guide lives at
[`skills/kerby/CLAUDE.md`](skills/kerby/CLAUDE.md) — read it before changing rule text
(every rule carries a recurring input-token cost; each should trace to a real past
failure). Run `python3 scripts/check-skill-compat.py` after any frontmatter or
version-bearing change, and `bash scripts/check-plan-gate-parity.sh` after any
change to the plan_threshold default or the grade-≥7 approval point (it fails if
those constants drift across the files that restate them — BOOTSTRAP, the
workflows, working-patterns, the schema, the template; the checked set is listed
in the script). If you add a new restatement, add the file to that set.

The product voice — how kerby *talks* in the README, verdict output, and CHANGELOG — is
specified in [`VOICE.md`](VOICE.md). Read it before editing any persona-bearing copy; the
rules and command references stay literal regardless (see its Zoning table).

---

## PR Workflow (repo default)

After opening a PR (base `main`):

0. **Always @codex.** On PR creation AND after every fix push, post a comment mentioning `@codex review` to (re)trigger a review — don't rely on auto-review.
1. **Poll for Codex review comments every ~5 minutes.** Codex (`chatgpt-codex-connector` bot) reviews on PR open or a `@codex review` comment. Fetch with `gh api repos/{owner}/{repo}/pulls/<n>/comments` (inline), `gh pr view <n> --json reviews` (review comments), AND `gh api repos/{owner}/{repo}/issues/<n>/reactions --paginate` — Codex signals "no further suggestions" with a 👍 **reaction on the PR itself**, not always a review comment. Use `--paginate`: GitHub's reactions endpoint defaults to 30 per page and `gh api` does not auto-paginate, so on a PR with 30+ reactions a plain call can silently miss Codex's 👍 and read a real approval as silence, misfiring the silence cap below.
2. **Address each comment** — fix if valid; **push back if you disagree** (surface disagreement, don't comply blindly). Commit + push fixes, reply on the PR, and re-trigger with a `@codex review` comment. Keep going round after round until clean — don't pause to ask.
3. **Merge on either green light** (`gh pr merge --squash --delete-branch`), which overrides kerby's "leave for human review" guardrail for this repo — **both paths require the evidence to be against the current head commit**; an approval, reaction, or silence window from *before* the latest push doesn't count, since the whole point is independent review of what's actually about to ship. **Squash is the default merge method** — this repo keeps one commit per PR on `main`; don't use `--merge` or `--rebase` without being asked. **Always pass `--delete-branch`** — this repo's `deleteBranchOnMerge` setting is off, so GitHub won't clean up the head branch on its own, and a stale branch left behind after every merge is a real (not hypothetical) cost on a repo that ships this many small PRs:
   - **Codex approves** — a review/comment against HEAD saying the code looks good / no issues (check `commit.oid` matches HEAD in `gh pr view <n> --json reviews`), OR a `chatgpt-codex-connector[bot]` 👍 reaction on the PR. Reactions carry no commit SHA, so freshness is timestamp-based instead: the reaction's `created_at` must be after the latest push (or after the `@codex review` trigger comment that followed it) to count as evidence against the current head. Either form: merge immediately, don't wait out the timer. A stale approval or reaction from before a later fix push does not satisfy this.
   - **10-minute silence cap (mandatory, conditional)** — if Codex posts no new comments for 10 minutes after the **latest push**, merge once comments are addressed — but only once **at least one completed Codex review exists against the current head commit**. If Codex never reviewed the current head at all (connector down, unauthorized, rate-limited), silence is not a green light — it's a missing gate, not a passed one. Escalate to a human instead of merging. This exception is load-bearing for any PR touching rule text under `skills/kerby/`, where `skills/kerby/CLAUDE.md`'s gate table already makes independent review HARD before merge — the silence cap must never be the mechanism that lets a rule-text change ship with zero independent review. The cap **resets on every push** (each fix gives Codex a fresh 10-minute window).
