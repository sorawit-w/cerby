# Changelog

All notable changes to `cerby` are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); versioning is semver.

## [4.22.0] — 2026-06-20

Two `audit` runs over the same repo state diverged in layout — the HTML chrome was
already deterministic, but the Markdown **body** wasn't: §6 defined finding *fields*
without a layout, and §7 said "grouped by dimension, sorted by severity" without
pinning list-vs-table. Each run improvised the body. Fix: **pin the body structure**
and give the audit its **own render template** so the same findings always produce a
structurally identical report.

### Added
- **`skills/cerby/resources/templates/audit-report.html.template`** — a dedicated
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
should be ported into cerby. Finding: **cerby already implements it, often as the
origin** — tiers are mechanically hook-enforced (stronger than a review annotation),
provenance lives in `NOTICE` + dated inline citations, eval grading is delegated to
`skill-evaluator`, and the harness/control-loop vocabulary is in the root `CLAUDE.md`.
The one genuinely-novel agent-skills mechanism — the cross-skill co-load regression
gate — is N/A for a single skill. So nothing was ported; one fixture was added.

### Added
- **`.eval/triggers/cerby.json`** — a committed trigger-eval boundary corpus
  (should-fire / should-not-fire / neighbor-steal) protecting cerby's sharp
  "do NOT invoke on general coding tasks" boundary, including the load-bearing case
  that a general "security review of my repo" must NOT fire (cerby `audit` is
  conformance-to-cerby, not a general bug/security review). The fixture is labeled
  data the skill owns, not a runner: triggering-accuracy runs are `skill-creator`'s
  `run_eval` job (NOT `skill-evaluator`, which audits rule adherence), and no gate
  auto-runs it — it is a manual regression checklist for description edits.
- **`skills/cerby/CLAUDE.md`** — a short note recording why the conventions layer is
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

First release under the **`cerby`** name. The skill was extracted from
[`sorawit-w/agent-skills`](https://github.com/sorawit-w/agent-skills) — where it shipped
as `coding-rules` through v4.21.0 — into this standalone repo, with full commit history
preserved (`git log`). The version number is continuous with the `coding-rules` line; the
rename is the only change in this release.

### Changed
- **Renamed `coding-rules` → `cerby`** everywhere: skill `name`, trigger phrases, the
  `/cerby` invocation, the `CERBY_DIR` env var, hook-path signatures, glob discovery, and
  all prose. `coding-rules` is no longer recognized — invoke `cerby` (or `/cerby`).
- **Standalone packaging.** Own plugin manifests (Claude Code, Codex, Cowork), own
  `check-skill-compat.py`, vendored harness-engineering vocabulary in the repo-root
  `CLAUDE.md`. Sibling skills it used to be bundled with (`sub-agent-coordinator`,
  `team-composer`, `i18n`, `tech-stack-recommendations`, `brand-workshop`) are now
  optional external pointers to `sorawit-w/agent-skills` with graceful fallback.

### Notes
- Prior per-version history (v4.0–v4.21.0 under the `coding-rules` name) lives in the
  preserved git history and in the `sorawit-w/agent-skills` CHANGELOG.
- **Breaking:** anyone invoking `/coding-rules` must switch to `/cerby`. There is no
  back-compat alias by design — `cerby` is a clean-identity repo.
