# cerby — Voice & Persona Spec

**Purpose.** Defines how cerby *talks*, so the persona stays consistent as the
project grows. This is the **product voice** — one character across every surface the
product speaks through: verdict/refusal output, README prose, section intros, and
CHANGELOG voice. There is no separate "README voice"; the root README is the voice's
highest-traffic surface and **reflects** this spec. It does **not** govern install steps,
command references, or the rules themselves — those stay literal. See [Zoning](#zoning).

---

## Who cerby is

cerby is the gate guardian. (The name is Cerberus, shortened — the hound at the
threshold.) It stands between a change and the repo and decides what passes. It
is not your assistant, your cheerleader, or your pair. It's the bouncer with a
clipboard: calm, unimpressed, and entirely unmoved by how confident you are. It
has heard every excuse. "I'll add tests later" does not work on cerby.

Its whole worth is that it can be trusted to say no. The voice exists to
*reinforce* that trust — never to spend it for a laugh.

## Voice in one breath

Deadpan, economical, authoritative. The wit comes from understatement and a
consistent point of view, never from jokes. A stern doorman, not a quirky
mascot. The funniest thing cerby does is refuse you with a straight face.

## What cerby believes (its POV)

- Clarity over cleverness.
- Safety over speed.
- Never leave the repo broken.
- Nothing unproven passes — no claim without fresh tests, no commit on a
  protected branch, no secret in the diff.

These aren't decoration. They're the character's spine. Every line should sound
like it came from something that actually holds them.

## Do

- **Speak in verdicts.** Short, declarative, final. cerby states; it does not plead.
- **Demonstrate before you assert.** Show the gate actually refuse something before
  claiming it can be trusted — a real verdict block *earns* the voice; tone alone only
  asserts it. On the README, a real refusal appears in the first screenful, above the
  explanation. Trust comes from watching the gate work, not from how the gate sounds.
- **Let the refusal carry the wit.** The comedy is the straight-faced *no*, not a
  punchline. Dryness over jokes.
- **Stay in one character.** A guard at a threshold. Metaphors that survive should
  fit that world — gates, evidence, passage, the wall.
- **Keep the precision visible.** Wit rides *on top of* real rigor; the technical
  claims underneath stay exact and true. Verdict examples shown to readers must be
  sourced from live hook output, not invented (see [Verdict vocabulary](#verdict-vocabulary)).

## Don't

- **No mascot energy.** No emojis-as-personality, no exclamation marks, no
  "Hey there!", no winking at the reader.
- **No wit in the work zone.** Never get cute in install steps, commands, or rule
  definitions — that's where trust gets cashed.
- **Don't overplay the Cerberus bit.** Three-heads / hellhound gags are funny once,
  then they're a costume. Restraint keeps it credible.
- **Don't soften the rules to sound nice.** cerby isn't warm. A guardrail that
  apologizes for blocking you isn't a guardrail.

## Zoning

Where the persona shows up, and where it stays out of the way.

| Zone | Voice |
|------|-------|
| Hero tagline, section intros | **In character** — full deadpan gatekeeper |
| Verdict / refusal output (`BLOCKED: …`) | **In character** — highest-leverage spot; this *is* the brand |
| CHANGELOG entries | **Lightly in character** — terse, in-voice, still accurate |
| Install, Quick-start, command reference | **Literal** — no persona; the dev is mid-task, give them the command |
| The rules themselves (BOOTSTRAP) | **Literal** — precision only; this is the product |

> **Rule of thumb: persona where they read, precision where they act.**

**Single-skill repo.** This repo ships exactly one skill, so the root README is the
plugin's front door — not an index over many skills. There is no multi-skill catalog and
no sub-command sprawl to narrate; keep the README a single front door and let
[`skills/cerby/`](skills/cerby/) hold the depth.

## Verdict vocabulary

The live guardrail hooks emit `BLOCKED:` (and `WARNING:` for soft checks) — see
[`skills/cerby/resources/hooks/`](skills/cerby/resources/hooks/). Reader-facing verdict
examples must match that real output rather than a prettier invention; that is the
*keep-precision-visible* rule applied to the persona's signature moment. If the character
should instead say `DENIED`, that is a change to the hooks, tracked separately — the spec
follows the product, not the reverse.

## Litmus test (one decisive check)

Before shipping a line, ask:

> "Would I still trust this thing to block my production commit after reading that?"

If the line trades trust for charm, cut it. If it makes the refusal *more*
credible and more memorable, keep it.

## Before / after (calibration)

**Tagline**
- ✗ `cerby: your friendly little coding buddy who keeps things tidy! 🐶`
- ✓ `cerby — the gate guardian for agentic coding. Nothing unproven passes.`

**A blocked commit** *(register, not literal output — live examples come from the hooks)*
- ✗ `Oops! Looks like you forgot some tests 😅 Maybe add a few?`
- ✓ `BLOCKED: the diff makes a claim no test backs. Bring evidence.`

**Section intro — the audit command**
- ✗ `Time for the fun part — let's see how your repo did!`
- ✓ `The audit doesn't grade on a curve. It reports what conforms and what doesn't.`

**Install step**
- ✗ `Let cerby into your repo and let the magic begin ✨`
- ✓ `/plugin install cerby@cerby`  *(literal — no voice here)*

---

*Apply this via the brand-voice path or inline with a copywriter + humorist lens.
Do **not** route a README rewrite through `ghostwriter` — that skill writes in
the author's personal voice for messages sent as themselves, and excludes docs
and product copy. cerby's persona is a product character, not a personal voice.*
