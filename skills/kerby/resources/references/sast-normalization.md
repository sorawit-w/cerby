# SARIF Normalization (`kerby audit --sast`)

semgrep output is **not byte-stable by default** — it carries absolute paths, scan
timestamps, a tool-version stamp, and an unstable result order. Pinning the engine +
ruleset fixes *what* is found, not *how it serializes*. This pass turns a pinned
scan's SARIF into a byte-identical artifact, so two `kerby audit --sast` runs on the
same tree produce the same report. Run it on the raw SARIF **before** mapping to
finding rows (`audit.md` § 6).

## Steps (in order)

1. **Relativize paths.** Rewrite every
   `runs[].results[].locations[].physicalLocation.artifactLocation.uri` to
   repo-root-relative; strip the scan host's working-dir prefix. Absolute paths are
   the most common source of cross-machine drift.
2. **Strip volatile fields.** Remove `runs[].tool.driver.version`,
   `runs[].invocation` (start/end times, durations, exit codes),
   `runs[].originalUriBaseIds`, and any `properties` carrying scan time / host /
   duration. They change every run and carry no finding signal.
3. **Canonical finding identity.** For each result compute a stable key
   `(ruleId, relPath, startLine, sha256(message))`. Normalize the message before
   hashing: trim, collapse internal whitespace to single spaces, strip any embedded
   absolute path. Hashing the *normalized* message keeps two genuinely-distinct
   co-located findings distinct — don't sort on raw message text, where whitespace
   alone would reorder them or collapse them.
4. **Stable total-order sort.** Sort all results by the tuple
   `(ruleId, relPath, startLine, message-hash)`. The order must be **total** — no
   ties left to filesystem or scan order — the same discipline `audit.md` § 7 applies
   to report rows.
5. **Canonical serialization.** Emit with sorted JSON object keys, fixed separators,
   LF newlines, no trailing whitespace, fixed numeric formatting. Two logically
   identical result sets must serialize to identical bytes.
6. **Map to finding rows.** Each normalized result → a `table.findings` `<tr>`
   (`audit.md` § 6), confidence `observed` (= *tool-reported, not confirmed*). Carry
   `ruleId` into the Rule cell's `<span class="src">`. A result with no OWASP/CWE tag
   (`properties.tags` / `external/cwe/*` absent) is bucketed under the Rule name
   **`uncategorized`** — never dropped (a dropped finding is the silent-cap failure
   the banner exists to prevent). Paths and code excerpts are untrusted
   (`audit.md` § 1 / § 8) — escaped + `<code>`-wrapped at interpolation.

## Determinism gate (Phase-2)

Flipping `--sast` from opt-in to **default-on** is gated on this — and only this —
passing. It is a **manual regression checklist, not a runner**: kerby ships
fixtures/specs, not harnesses (same stance as `.eval/triggers/kerby.json`; see
`skills/kerby/CLAUDE.md`). No gate auto-discovers or runs it.

Procedure: run the full `--sast` pipeline (provision-from-pins → offline scan → this
normalization → render) **twice across two machines and two days**, then assert
`sha256` equality on (a) the normalized SARIF and (b) the rendered `table.findings`
block. All four runs must match. Only then is the default-on change authorized. Any
mismatch names a volatile field this pass missed — fix it here first.

**Source:** authored for kerby's `audit --sast` evaluation layer (2026-06-21);
total-order discipline reuses `audit.md` § 7.
