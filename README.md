<p align="center">
  <img src="assets/kerby-hero.png" alt="kerby — the gate guardian for agentic coding" width="280"/>
</p>

<h1 align="center">kerby</h1>

<p align="center"><em>The gate guardian for agentic coding. Nothing unproven passes.</em></p>

---

kerby stands between a change and your repo and decides what gets through. It is not your
pair, your assistant, or your cheerleader. It has heard "I'll add tests later" before. It
was not moved then either.

The job is one motion — **GATE → WEIGH → VERDICT**. A change arrives at the gate. kerby
weighs it against the evidence. Then it passes, or it doesn't. No claim without a fresh
test behind it. No commit on a protected branch. No secret in the diff.

![kerby's one motion: a change arrives, kerby weighs it against the evidence, and the verdict is binary — the change passes or it is BLOCKED and the action stops.](assets/gate-motion.svg)

The same motion runs whatever the work is — that work routes into task-shaped playbooks
(feature, bugfix, and three more); the [skill README](skills/kerby/README.md#workflows) maps them.

## What it looks like when kerby says no

This is not prose about the product. This is the product. When an agent reaches for
something that can't be undone, kerby answers in stderr and the action stops:

```
BLOCKED: git push --force / -f
Reason: destructive git command — data loss is hard or impossible to undo.
If you really need this, run it yourself in a terminal.
See kerby guardrails (hooks/protect-git.sh).
```

```
BLOCKED: Do not edit .env files directly. Use environment variables and
document required vars in DEVELOPER_TODO.md. See kerby guardrails.
```

```
WARNING: gitleaks detected possible secrets in staged changes.
Output suppressed so the secret isn't echoed here — inspect locally with
'gitleaks stdin --redact', or allowlist a false positive in the scanner's config.
```

No tone to argue with. The gate is open or it isn't.

## What it is

kerby is a loadable **rule-corpus + opt-in guardrail hooks** that govern how an AI coding
agent works. The rules shape how ordinary coding tasks get done; they don't do a task
themselves. The hooks enforce the few rules that must never be left to memory —
destructive git, `.env` edits, secrets in a commit — mechanically, every time.

You can load the rules for a session, install the hooks per project for standing
enforcement, prepare an existing repo, or audit a repo against the rules.

> Formerly shipped as `coding-rules` in
> [`sorawit-w/agent-skills`](https://github.com/sorawit-w/agent-skills); extracted here
> with full history. **Invoke `kerby`, not `coding-rules`.**

## Install

```
/plugin marketplace add sorawit-w/kerby
/plugin install kerby@kerby
```

Or via the cross-platform CLI:

```
npx skills add sorawit-w/kerby
```

## Quick start

```
/kerby             # default: load the rules into the session
/kerby reload      # re-load after a context compaction
/kerby status      # check whether the rules are still active
/kerby install     # persistent per-project setup (guardrail hooks)
/kerby uninstall   # mirror — removes the managed hooks
/kerby prepare     # onboard an existing repo (populate .ai/ context)
/kerby audit       # conformance audit → HTML report
```

## What kerby holds

These are not decoration. They are what every verdict comes back to:

- **Clarity over cleverness.** Code is read more than it's written.
- **Safety over speed.** A fast change that breaks the repo cost you time, not saved it.
- **Never leave the repo broken.** The gate closes behind you, not just in front.
- **Nothing unproven passes.** Evidence, or it doesn't ship.

## Documentation

- **[`skills/kerby/README.md`](skills/kerby/README.md)** — full user guide: what it does,
  when to use it, the loader behavior, and the per-project install.
- **[`skills/kerby/SKILL.md`](skills/kerby/SKILL.md)** — the skill body (sub-command
  routing, install/uninstall mechanics).
- **[`skills/kerby/resources/BOOTSTRAP.md`](skills/kerby/resources/BOOTSTRAP.md)** — the
  rules themselves.
- **[`CLAUDE.md`](CLAUDE.md)** — the harness-engineering vocabulary kerby implements.

## Status

Current release: `5.8.0` — closes the **repeated-literal drift gap**. `working-patterns.md`
long told agents to *inline until a second caller forces the seam* but said nothing about what
to do once that caller arrives — so the same allowed-values array gets re-typed at each call
site, copies drift, and a bare literal has no IDE find-usages. The new **Hoist repeated
literals to a single named source** rule names the move for that moment and draws a hard line
between *deduplication* (one named in-code constant) and *externalization* (config/env), which
the existing hardcoded-value rule still governs. See [CHANGELOG.md](CHANGELOG.md).

Prior release: `5.7.0` — closed the **hollow-pass gap**. `validation.md` long *named* the
green runs that prove nothing — always-true assertions, `.only`/`.skip` focused suites — but
naming a fake is not catching one. `pre-commit-check.sh` now reads the diff: over the *added*
lines of staged test files it statically flags focused/disabled markers and always-true
assertions, as a soft advisory (counts only, never echoing a test line).

**Opinionated — read first.** These are one author's rules. Read
[`skills/kerby/resources/BOOTSTRAP.md`](skills/kerby/resources/BOOTSTRAP.md) end-to-end
before adopting, and fork-and-edit rather than file feature requests on rule content.

## License

MIT — see [LICENSE](LICENSE). Third-party attributions in [NOTICE](NOTICE).
