# SAST Provisioning (`kerby audit --sast`)

How the pinned, offline SAST toolchain gets set up. **On-demand, agent-driven,
cached per project** — triggered when `kerby audit --sast` is requested and the
toolchain isn't already resolvable. It is **not** part of `prepare`: onboarding
installs no tooling (`workflows/adopt-existing.md` ring-fence).

**One invariant: all network at setup, none at scan.** The scan reads code and the
provisioned snapshot only. If a pin can't be resolved at scan time, the check is
`not-run` (`audit.md` § 5) — never a live fetch, never an error.

## Where the pins live

Project-owned, in `agent-context.yaml` `stack.tools.sast` (schema:
`agent-context.schema.yaml` § `SastTools`). kerby *resolves* these pins; it never
tracks upstream or bumps them. Keeping them current is the project's job (its
dependency bot), surfaced as a freshness line in the report banner — the same
ownership model as the dead-code linter (`audit.md` § 5). Methodology travels,
scripts don't: kerby ships this procedure, not the pins and not the scanners.

## Where it installs

An out-of-tree, **git-ignored** toolchain dir — `.ai/sast/` by default — holds the
**generated** artifacts only: the venv, the vendored ruleset, the advisory snapshot.
**Never repo source.** This keeps the audit's read-only-on-the-repo contract and the
"No source files changed" completion claim true: provisioning writes only under
`.ai/sast/`, the scan writes only the report under `.ai/audits/`. `audit.md` § 5 (top
contract) and § 7 (write rule) explicitly list this cache as the one permitted
non-source write under `--sast` — so honoring both docs is unambiguous.

The hash-locked **requirements lockfile is a committed, versioned input** — it lives
**outside** the `.ai/sast/` cache (e.g. `sast/requirements.lock`), because it must be
present on a fresh checkout / teammate machine for the install to be reproducible. If
it lived in the git-ignored cache it would be absent on clone, and provisioning would
silently degrade to `not-run` — defeating the determinism the pin exists to give.
Pins in `agent-context.yaml` + the committed lockfile are the reproducible *inputs*;
`.ai/sast/` is the disposable, regenerable *output*.

## Procedure — default: pinned venv, no Docker

Do all of this at setup; run only the steps whose tool isn't already present at the
pinned version.

1. **Python.** Use the pinned interpreter (`stack.tools.sast.python`). semgrep
   behavior can shift across minor versions, so the interpreter is part of the pin.
2. **semgrep + Python deps.** Create the venv under `.ai/sast/` (generated, cache) and
   install from the **committed** hash-locked lockfile: `pip install --require-hashes
   -r <stack.tools.sast.requirements>`. The lockfile is a versioned repo input, not a
   cache artifact (see "Where it installs"). `--require-hashes` makes the install
   *fail* rather than silently drift if any byte differs from the pin.
   `semgrep==<version>` alone is **not** reproducible — the lockfile pins every
   transitive dep + its hash.
3. **Ruleset.** Vendor the pinned semgrep ruleset
   (`stack.tools.sast.semgrep.ruleset`) into `.ai/sast/` so the scan resolves it
   offline. Pin to a ruleset revision/hash, not a moving registry tag.
4. **Advisory DB.** Fetch the pinned advisory snapshot
   (`stack.tools.sast.advisoryDb.snapshot`) into `.ai/sast/`. The dependency check
   runs against this snapshot **only** — never a live query (`audit.md` § 5). Record
   its `date` so the banner can state freshness.
5. **gitleaks.** Already provisioned by `hooks/pre-commit-check.sh` (betterleaks /
   gitleaks if present, else the regex floor). Referenced, never re-pinned here.

All network fetches happen here, at setup. After this the scan is fully offline.

**Verify before declaring provisioned:** each pinned tool resolves and reports its
pinned version from the cache, and the ruleset + snapshot files exist. Any missing
piece → that check degrades to `not-run` at scan time, not an error.

## Container variant (deferred)

An egress-locked container (image pinned by **digest**, ruleset + snapshot vendored
in, deps DB offline) is the only option reproducible down to the OS, for true
isolation. **Out of scope for v1** — the venv path above ships first. Noted here so
the pins schema (`python`, `requirements`) needn't change when it lands.

<out_of_scope>
## Out-of-scope ring-fence

- **Not part of `prepare`.** Onboarding installs no tooling
  (`workflows/adopt-existing.md` ring-fence). Provisioning is an audit-time `--sast`
  concern.
- **kerby ships no scanner binaries and no pins of its own** — only this procedure.
  The project owns the pins (`audit.md` § 5 dead-code convention).
- **No live / network scans, ever.** Network is a setup-only activity.
- **No repo-source or `.gitignore` writes.** Provisioning touches only the
  git-ignored `.ai/sast/` cache.
- **No CodeQL or any engine** beyond semgrep + the advisory snapshot + the existing
  gitleaks.
</out_of_scope>

**Source:** authored for kerby's `audit --sast` evaluation layer (2026-06-21);
pins-in-`agent-context` mirrors the dead-code linter resolution in `audit.md` § 5.
