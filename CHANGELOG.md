# Changelog

All notable changes to `kerby` are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); versioning is semver.

## [5.6.0] — 2026-06-25

Closed the **commit-on-protected-branch gap** in `protect-git.sh`. The hook previously
blocked only `git push` to a protected branch and `git push --force`; `git commit` while
*on* a protected branch was allowed (it was in the hook's own ALLOW test set). So an agent
that forgot to branch would commit straight onto `main`/`develop` and only hit a wall at
push time — leaving local commits on a protected branch to unwind. This is the
intermittent, agent-to-agent-varying failure that prose rules alone (BOOTSTRAP "never work
on protected branches") couldn't stop, because prose enforcement is probabilistic.

Added (`hooks/protect-git.sh` section 7):

- **Commit-time gate.** Hard-blocks `git commit` (incl. `--amend`) when the **target**
  repo is on a protected branch (`main`, `master`, `dev`, `develop`, `staging`, `trunk`,
  `release/*`). This is the hook's first check that reads live repo state, not only the
  command string. It parses the git **subcommand** (so `git log --grep=commit` is not a
  commit), matches global options by shape plus the finite set of value-taking globals
  (both `--opt=val` and space forms), and resolves the target repo from `-C` **or**
  `--git-dir` — so `git -c k=v -C <path> commit` and `git --git-dir=<path> commit` (the
  bare-repo / dotfiles pattern) probe the right repo's branch, not the hook's cwd. In a
  compound command, the command is walked by segment (`&&`/`||`/`;`), **every** commit
  invocation is checked (not just the first), and a leading `cd <path>` is honored so a
  bare commit is checked against the branch of the directory it actually runs in
  (`cd /repo && git commit`). A
  single PreToolUse pass can't fully model runtime git — relative cumulative
  `-C`/`--git-dir` and quoted-space paths are a documented residual (see
  `references/threat-model.md`).
- **Scoped, per-command override.** `CODING_RULES_ALLOW_PROTECTED_COMMIT=1` bypasses
  **only** the commit gate, for commits the user explicitly authorized. The hook detects
  the assignment **in the command string**, and only when it directly prefixes the git
  commit (`CODING_RULES_ALLOW_PROTECTED_COMMIT=1 git commit …`) — a PreToolUse hook runs
  before the command, so it can't read the child shell's env. An ambiently-exported var,
  or the token appearing elsewhere in the command (an `echo` arg, a commit message, a
  different `&&` segment), is deliberately **not** honored — all are self-bypasses. The
  destructive blocks (force-push, `reset --hard`, `clean -f`, `branch -D`, wholesale
  discard) remain non-disablable. A new BOOTSTRAP line scopes the override behaviorally:
  set it only on explicit authorization, never to self-bypass.
- **Carve-outs** to fire only on the real mistake: the repo's first-ever commit (unborn
  HEAD) and detached HEAD. Compound branch-create-then-commit one-liners
  (`git switch -c x && git commit …`) are **not** carved out — a PreToolUse hook can't
  prove the commit lands off the protected branch (the switch may fail, the new branch
  may itself be protected like `release/*`, `;` runs the commit regardless), so branch
  creation and the commit must be **separate** commands.

Block-and-instruct, not auto-switch: the hook tells the agent to create a feature branch
rather than silently creating one. Branch naming stays kerby-convention (`feat/`, `fix/`),
not a vendor-specific prefix. Docs synced: `guardrails.md`, `threat-model.md`, `BOOTSTRAP.md`.
Tests extended with real temp-repo cases (the string-only harness can't control the branch).

## [5.5.0] — 2026-06-25

Fixed the **soft-hook delivery channel**. A PreToolUse hook's stderr is surfaced to the
agent only on the exit-2 *block* path; on exit 0 the only channel the agent reads is
JSON-on-stdout (`hookSpecificOutput.additionalContext`). Two existing soft hooks were
therefore silently swallowed in real Claude Code — they "passed" only because their
self-tests captured the wrong stream:

- **`warn-env-read.sh`** emitted the `.env`-read reminder to stderr + exit 0. It now emits
  `hookSpecificOutput.additionalContext` on stdout, with **no** `permissionDecision` (the
  read proceeds through normal permissions — this only adds context).
- **`pre-commit-check.sh`**'s soft lint/test reminder `cat`'d plain text to stdout + exit 0
  (plain, non-JSON stdout is also ignored for PreToolUse). It is now wrapped as
  `additionalContext` JSON. The secret-scan hard-block (exit 2 + stderr) is correct and
  unchanged.

Both self-tests now assert the stdout-JSON path, that no `permissionDecision` is set, and
that nothing is written to stderr. `hooks.md`'s strictness lines and exit-code table are
corrected, with a gotcha note so future hook authors don't repeat the stderr-on-exit-0
mistake. (Same delivery mechanism the `route-high-stakes` hook shipped with in 5.4.0; this
back-fills the two pre-existing hooks.)

## [5.4.0] — 2026-06-25

Moved BOOTSTRAP §3's **high-stakes path override** from `[behavioral]` to
`[enforced-partial]`. A new `route-high-stakes` PreToolUse hook
(`hooks/route-high-stakes.sh`) matches every `Edit`/`Write` against §3's globs
(auth / schema migrations / payments / infrastructure / CI-CD) and, on a match,
reminds the agent that the change requires `workflows/feature.md` or `bugfix.md`
+ the §4 Plan Gate — not `quick-task.md`, even for a one-liner. It is advisory:
exit 0, injecting the reminder via stdout JSON (`hookSpecificOutput.additionalContext`,
the channel a PreToolUse hook's output actually reaches the agent on exit 0; it carries
no `permissionDecision`, so the edit still goes through normal permissions), disablable
via `CODING_RULES_HOOK_DISABLED=route-high-stakes` — routing is a decision, not a
destructive-action veto, so no new hard blocks.
The matched globs are embedded byte-identical to §3 and `route-high-stakes.test.sh`
asserts parity, so the hook and the rule can't silently drift. §3's prose-only
*production-traffic-shaping* category has no glob and stays `[behavioral]` — that
named gap is what keeps the tier `[enforced-partial]` rather than `[enforced]`.
Pattern absorbed concept-only from `paulDuvall/ai-development-patterns` (MIT) —
Progressive Disclosure; see `NOTICE`.

## [5.3.0] — 2026-06-22

Made the **complexity grade observable** and turned "plan first" into a hard gate.
`BOOTSTRAP.md` §2.5 ("Grade before you route") emits a `complexity:` line before routing
— always, even for one-liners — and a new §4 **Plan Gate** hard rule requires a written
plan with an **Expected Outcomes** block at grade ≥ `plan_threshold` (`ai.planThreshold`,
default 4) and STOP-for-approval at ≥7. The gate is behavioral — instructed, not enforced
— so the emitted plan is the proof it ran. `quick-task` is now reachable only when
`grade < plan_threshold`, unifying routing and the gate behind one knob.

The three divergent complexity tables collapse into **one canonical ladder**
(`feature.md §3`); `working-patterns.md` and `implementation-planning.md` point to it
(the latter keeping its Who/When delegation mapping). The finish step gains **Realized
Outcomes** — capture the actual run result (or dry-run transcript) as an evidence object,
emit `outcome: match | mismatch`, and route a mismatch to **code-wrong** (fix via the
existing loop + circuit breaker), **prediction-wrong** (update the prediction + log to
`.ai/memory.log`), or **ambiguous** (STOP for human adjudication). The Iron Law now
forbids editing realized evidence to match a prediction and judges on material intent.

Tightened by an in-session `skill-evaluator` pass: the opt-out trigger set drops the
bare word `quick` (it collided with casual openers like "quick question" and risked
silently skipping the plan) — only explicit skip-planning instructions count. The §3
high-stakes path override now states that routing is decided by *which file* an edit
lands in, not by whether the changed lines look security-relevant.

A Codex PR review closed four consistency seams in the unified model: (1) quick-task
eligibility now requires *both* `grade < plan_threshold` *and* the quick-task fit check
(so raising the knob can't route a moderate-logic task into a workflow that rejects it);
(2) a user opt-out now explicitly waives the Expected/Realized Outcomes comparison while
leaving the Verification rule and quality gates intact; (3) the §2.5 emitted route allows
the full §3 workflow set (`bugfix`/`new-project`/`adopt-existing`, not just
`quick-task`/`feature`) so a bug fix isn't forced to mislabel as a feature; and (4) the
Plan Gate's inline-plan path no longer stops grade 4–6 work — the approval STOP is scoped
to grade ≥ 7, matching the ladder; and (5) the Realized Outcomes check is now a §4 Plan
Gate hard rule (pointing to feature.md §7 as the canonical procedure) so it applies to
*every* workflow at grade ≥ threshold — a grade-4+ bug fix or setup task can no longer
finish without the match/mismatch classification; (6) that Realized-Outcomes rule is now
correctly scoped to §3-routed coding workflows in a loaded session — the standalone
`prepare`/`audit` sub-commands (which never run the §2.5 grading step) are governed by
their own diff-and-confirm / report procedures, not the gate; and (7) when a task outgrows
quick-task it now falls back to the task-type workflow (`bugfix.md` for a bug fix), not
unconditionally to `feature.md`, preserving the bugfix reproduce/diagnose/test path —
including `quick-task.md`'s own four internal escalation points, now aligned to the same
task-type rule.

Two harness-lens cleanups from the fresh-session skill-evaluator pass: the **How to Verify**
template is now defined once in BOOTSTRAP §4 and referenced by the four workflows +
validation.md (was duplicated five times), preserving each workflow's domain-specific
hints; and the `planThreshold` absent-config fallback is now explicit at first use ("if
the file or key is absent, use the default 4 — never block on the missing knob").

Further Codex-review fixes: the Plan Gate's no-approval band is now expressed relative to
the knob (`plan_threshold ≤ grade < 7`) instead of a hardcoded `4–6`, so a moved threshold
actually takes effect; the canonical ladder notes that its Plan entries assume the default
while the requirement tracks the knob (approval at ≥7 fixed); and quick-task escalations no
longer name "step 2 (Clarify)" — they point to the target workflow's own step 2 (Reproduce
in `bugfix.md`). Finally, `planThreshold` is capped at **7** (schema `maximum`, template
comment, and the §4 rule): approval is fixed at grade ≥ 7, so a higher threshold would make
grade-7 work require approval with no plan to review — 7 is the point where plan and approval
coincide. And the §2.5 summary line now frames the grade decision as
quick-task-vs-**task-type-workflow** (not quick-task-vs-feature), matching the task-type
fallback so an outgrown quick bugfix isn't described as routing to `feature.md`. A
consolidated self-audit then closed the last propagation gap: `bugfix.md` and
`new-project.md` finish steps now explicitly list the Realized Outcomes obligation (pointer
to feature.md §7), matching how Manual Verification is surfaced — the §4 hard rule no longer
relies on the agent cross-referencing it from a workflow that didn't mention it. Final
sweep of *every* `feature.md` routing mention (not just the escalation sections) caught
three the earlier passes missed — `quick-task.md`'s Branching note and "hard-floored"
rationale, and the §3 high-stakes override — all now route bug fixes to `bugfix.md`,
preserving its reproduce/diagnose/failing-test path even under the override.

## [5.2.0] — 2026-06-21

Added an **opt-in deterministic code-static security layer** to `kerby audit`.
`kerby audit --sast` runs the project's **pinned** semgrep (OWASP/CWE) and a **pinned,
offline dependency-advisory snapshot** alongside the existing gitleaks secrets check,
emitting findings through the existing report renderer. It is **off by default**;
default-on is deferred to a later phase behind a byte-identity gate. Findings are
**`observed` = tool-reported, not confirmed** — no artifact may claim the code is secure
or "OWASP-compliant" (same honesty stance as 5.1.0).

### Added
- **`--sast` flag** on the `audit` sub-command ([`SKILL.md`](skills/kerby/SKILL.md),
  [`audit.md`](skills/kerby/resources/references/audit.md) §5/§10): two new mechanical-band
  checks — **SAST (semgrep)** and **vulnerable dependencies** `[A06 · CWE-1104]` — added to
  the `security` dimension, both gated on `--sast`.
- **[`references/sast-provisioning.md`](skills/kerby/resources/references/sast-provisioning.md)** —
  agent-driven, on-demand, pinned toolchain setup (hash-locked requirements + pinned Python;
  no Docker). All network at setup, none at scan; installs to the git-ignored `.ai/sast/`
  cache, never repo source. Not part of `prepare`.
- **[`references/sast-normalization.md`](skills/kerby/resources/references/sast-normalization.md)** —
  the SARIF→byte-stable normalization pass (relativize paths, strip volatile fields, stable
  total-order sort, canonical serialization) + the Phase-2 default-on determinism gate
  (manual checklist, not a runner).
- **`stack.tools.sast`** in [`agent-context.schema.yaml`](skills/kerby/resources/agent-context.schema.yaml)
  (`SastTools` def) + a commented template block — project-owned pins (semgrep + ruleset,
  Python, hash-locked requirements, advisory snapshot). kerby resolves them; drift is the
  project's to manage, surfaced as a banner freshness line.
- **CSP + not-run visual state** in the audit HTML template — a restrictive
  `Content-Security-Policy` meta (no script, no external loads, no images) behind the §8
  escaping, and an amber `notrun` style so a `--sast`-requested-but-unprovisioned security
  section can't read as a clean pass.
- **Tier-2 registry row** ([`external-resources.md`](skills/kerby/resources/references/external-resources.md))
  for the opt-in agentic security dataflow pass — developer-run, never invoked by `audit`.

### Notes
- **Deterministic / read-only.** Pinned tools + offline scan + the normalization pass =
  `observed`, byte-stable findings; the scan reads code but writes only the report under
  `.ai/audits/`. Provisioning writes only to the `.ai/sast/` cache — "No source files
  changed" still holds.
- **Degrade, never hard-fail.** No pinned toolchain / advisory snapshot resolvable →
  `not-run` in the banner — never an error, never a clean pass.
- **Deferred:** default-on (Phase-2, behind the determinism gate), the non-deterministic
  `--review` adjudication pass, and the egress-locked container variant. **Out of scope:**
  CodeQL, compliance certification, bundling scanners.

## [5.1.0] — 2026-06-21

Mapped the **Security Lens** ([`validation.md`](skills/kerby/resources/references/validation.md)
§ Security Lens — Conditional Pass) to named, dated security standards and closed one
genuine coverage gap. The lens stays **conditional** and **`[behavioral]`** — it *targets*
these standards best-effort by agent judgment; nothing mechanically verifies conformance,
and no artifact may claim the code is "OWASP-compliant."

### Added
- **SSRF coverage** `[A10 · CWE-918]` — new trigger (*outbound requests to a user-influenced
  URL/host* — webhooks, unfurlers, fetchers, proxies, cloud metadata) plus a check item
  (allowlist destinations, block internal ranges + `169.254.169.254`, no redirect-following
  or DNS-rebinding into internal targets). This is the behavior-changing addition: the lens
  now fires on a surface the prior trigger list missed.
- **OWASP Top 10 (2021) + CWE tags** on every Security Lens check, plus `[A06 · CWE-1104]`
  on the dependency-review rule in [`guardrails.md`](skills/kerby/resources/references/guardrails.md)
  § Security Awareness. Tags are a dated citation, stamped against the 2021 list; `LLM01`
  references the separate OWASP Top 10 for LLM Applications.
- **A04 (Insecure design)** `[A04 · CWE-657]` and **A05 (Security misconfiguration)**
  `[A05 · CWE-16]` named as explicit check items. **A08** folded into the existing
  deserialization trigger as `[A08 · CWE-502/494]` rather than a duplicate bullet.
- **Non-certification honesty note** in the lens: targets the standards best-effort,
  `[behavioral]`, mapping is hand-maintained and not auto-tracked for drift.

### Notes
- **A09 (logging/monitoring) deliberately not named** — its "never log secrets" half is
  already the Secret-exposure check (`[A02 · CWE-200/532]`); its "log security events" half
  is ops scope-creep outside a coding lens.
- **`working-patterns.md` intentionally left untagged** — its platform-code security items
  are woven into prose, not a taggable list; tagging there spreads the citation-staleness
  liability for little gain.
- No tooling added (no SAST/CodeQL/SARIF); no change to `audit.md` or the `security` audit
  dimension; no third-party skill references.

## [5.0.0] — 2026-06-20

**Renamed the project from `cerby` to `kerby`.** The name now follows the Greek
**Kerberos** (Κέρβερος) — the hound at the gate — rather than the Latin *Cerberus*
the old name shortened. This is a breaking change: the plugin/skill install name
changed from `cerby` to `kerby`, so existing installs must reinstall under the new
name. Rules, hooks, workflows, and behavior are otherwise unchanged.

### Changed
- **Plugin identity** — `name`/`id`/`keywords`/URLs across `.claude-plugin/`,
  `.codex-plugin/`, and `.agents/plugins/` manifests now read `kerby`; repo URLs
  point to `github.com/sorawit-w/kerby`.
- **Skill** — `skills/cerby/` → `skills/kerby/`; SKILL.md `name: cerby` → `kerby`;
  all prose, references, hooks, templates, and the `.eval/triggers/` corpus updated.
- **Voice** — `VOICE.md` lore now derives the name from Greek *Kerberos* (Latin
  *Cerberus* noted as the later spelling).
- **Assets** — `assets/cerby-*.png` → `assets/kerby-*.png` (filenames + references).
  ⚠️ The bitmap artwork still renders the old wordmark and needs a redraw.

## [4.22.0] — 2026-06-20

Two `audit` runs over the same repo state diverged in layout — the HTML chrome was
already deterministic, but the Markdown **body** wasn't: §6 defined finding *fields*
without a layout, and §7 said "grouped by dimension, sorted by severity" without
pinning list-vs-table. Each run improvised the body. Fix: **pin the body structure**
and give the audit its **own render template** so the same findings always produce a
structurally identical report.

### Added
- **`skills/kerby/resources/templates/audit-report.html.template`** — a dedicated
  audit render template. Shares the generic `html-export.html.template` `:root` BASE-token
  contract (so `DESIGN.md` overrides through one surface) and adds the audit-only layer:
  coverage banner, `table.findings`, severity badges, confidence styling, `--measure: 52rem`,
  and **fixed** semantic `--sev-*` status tokens (a brand palette can't make "blocker"
  stop reading as danger).

### Changed
- **`references/audit.md` §6** — a finding is now a `<tr>` in a raw-HTML `table.findings`
  with a fixed five-column order, not a Markdown bullet list. The raw-HTML scaffolding is
  the only trusted markup; cell *content* is entity-escaped + wrapped in a literal
  `<code>` element (Markdown backtick spans are inert inside the passed-through block —
  §8 step 2's backtick rule governs Markdown body text, not cell content).
- **`references/audit.md` §7** — the report skeleton is pinned to one exact top-to-bottom
  order (title → banner → summary → per-dimension tables → footer). Dimension sections
  follow the §10 stable-map order and same-severity rows tie-break by Location, so the
  ordering is *total* (no filesystem/git-discovery drift between runs). The banner is
  emitted as raw HTML. Zero-findings renders the banner + "No violations among the
  statically-checkable rules in scope" — never a bare ✓.
- **`references/audit.md` §8** — the render now wraps in `audit-report.html.template`. The
  untrusted-input escaping + self-check obligations are unchanged.
- **`references/html-export.md`** — the "one sanctioned exception" note now says the audit
  reuses the fill-and-override *machinery* and token contract via its **own** template, not
  the generic one. Docs stay honest.

### Notes
- MINOR (additive, user-visible output-format change). Determinism is the acceptance bar:
  same findings + same corpus → structurally identical report. No new checks, no hook
  changes, `BOOTSTRAP.md` untouched.

## [4.21.2] — 2026-06-19

A `team-composer` audit asked whether the agent-skills v5.2.0 "library-conventions"
layer (authority tiers / supply-chain / co-load regression gate / state-passing)
should be ported into kerby. Finding: **kerby already implements it, often as the
origin** — tiers are mechanically hook-enforced (stronger than a review annotation),
provenance lives in `NOTICE` + dated inline citations, eval grading is delegated to
`skill-evaluator`, and the harness/control-loop vocabulary is in the root `CLAUDE.md`.
The one genuinely-novel agent-skills mechanism — the cross-skill co-load regression
gate — is N/A for a single skill. So nothing was ported; one fixture was added.

### Added
- **`.eval/triggers/kerby.json`** — a committed trigger-eval boundary corpus
  (should-fire / should-not-fire / neighbor-steal) protecting kerby's sharp
  "do NOT invoke on general coding tasks" boundary, including the load-bearing case
  that a general "security review of my repo" must NOT fire (kerby `audit` is
  conformance-to-kerby, not a general bug/security review). The fixture is labeled
  data the skill owns, not a runner: triggering-accuracy runs are `skill-creator`'s
  `run_eval` job (NOT `skill-evaluator`, which audits rule adherence), and no gate
  auto-runs it — it is a manual regression checklist for description edits.
- **`skills/kerby/CLAUDE.md`** — a short note recording why the conventions layer is
  not ported and why a trigger fixture coexists with "ships no eval harness."

### Changed
- **`.gitignore`** — un-ignored `.eval/triggers/` only (`.eval/*` + `!.eval/triggers/`)
  so the boundary corpus is committed while the rest of `.eval/` stays local scratch.

### Notes
- Backwards-compatible (PATCH). No rule text or `SKILL.md` description changed, so no
  `skill-evaluator` gate fired. Fixture + docs only; no eval harness shipped.

## [4.21.1] — 2026-06-17

### Fixed
- **`prepare` now degrades cleanly on a repo with no git history.** `adopt-existing.md`
  issued the `git log` decision-scan and `git branch --show-current` as unconditional
  steps with no fallback, leaving the no-git case undefined — an agent could stall or
  `git init` unprompted (a repo-state change the ring-fence forbids). It now populates the
  code-derived artifacts only, skips the git-history knowledge scan, records the branch as
  `n/a (no git)`, and never `git init`s — mirroring `audit`'s existing no-git stance.
  Surfaced by a `skill-evaluator` absent-state audit.

## [4.21.0] — 2026-06-17

First release under the **`kerby`** name. The skill was extracted from
[`sorawit-w/agent-skills`](https://github.com/sorawit-w/agent-skills) — where it shipped
as `coding-rules` through v4.21.0 — into this standalone repo, with full commit history
preserved (`git log`). The version number is continuous with the `coding-rules` line; the
rename is the only change in this release.

### Changed
- **Renamed `coding-rules` → `kerby`** everywhere: skill `name`, trigger phrases, the
  `/kerby` invocation, the `KERBY_DIR` env var, hook-path signatures, glob discovery, and
  all prose. `coding-rules` is no longer recognized — invoke `kerby` (or `/kerby`).
- **Standalone packaging.** Own plugin manifests (Claude Code, Codex, Cowork), own
  `check-skill-compat.py`, vendored harness-engineering vocabulary in the repo-root
  `CLAUDE.md`. Sibling skills it used to be bundled with (`sub-agent-coordinator`,
  `team-composer`, `i18n`, `tech-stack-recommendations`, `brand-workshop`) are now
  optional external pointers to `sorawit-w/agent-skills` with graceful fallback.

### Notes
- Prior per-version history (v4.0–v4.21.0 under the `coding-rules` name) lives in the
  preserved git history and in the `sorawit-w/agent-skills` CHANGELOG.
- **Breaking:** anyone invoking `/coding-rules` must switch to `/kerby`. There is no
  back-compat alias by design — `kerby` is a clean-identity repo.
