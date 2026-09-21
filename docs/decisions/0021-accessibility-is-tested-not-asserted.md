# 0021 — Accessibility is tested, not asserted

**Status:** accepted, 2026-09-21

## Context

"Accessible" is easy to claim and hard to evidence. The usual artefact is a
statement page, which proves nothing about the code.

## What standard applies

There is no accessibility standard with legal force over a personal Android
app in Ontario. Worth stating plainly rather than implying otherwise:

- **AODA** requires WCAG 2.0 AA, but its scope is public-facing *websites and
  web content* for organisations of a certain size. A native app is outside
  it, and so is a personal project.
- **WCAG 2.2** is written for web content. The W3C publishes guidance on
  applying it to mobile, but conformance is not directly defined for a native
  app.
- **EN 301 549** does cover mobile applications and references WCAG. It binds
  public-sector procurement in the EU. Not applicable here.

So WCAG 2.2 AA is used as a **reference**, adapted, alongside Android's own
platform expectations — TalkBack, 48dp targets, and honouring the system font
scale. Claiming formal conformance would be a claim nobody has audited.

## Decision

Four checks run in CI on every push:

1. **Text scaling at 130% and 200%.** A `Row` overflows by throwing, and a
   thrown layout error fails a widget test, so this is a real assertion.
2. **`androidTapTargetGuideline`** — the 48x48dp minimum.
3. **`labeledTapTargetGuideline`** — every tappable has something for a screen
   reader to announce.
4. **`textContrastGuideline`** — Flutter's own check, against rendered pixels
   rather than against a palette, so it reaches Material-derived colours no
   audit of my own constants would.

## What this does not prove

None of it proves the app is usable with TalkBack. Screen reader behaviour
needs a screen reader, and a person who relies on one. What these prove is
that the conditions under which it becomes unusable are absent — unlabelled
controls, targets too small to hit, text that throws when enlarged, colours
too close to read.

That gap is the honest limit of automated accessibility testing, and the
reason the README says "tested against" rather than "compliant with".

## What the audit found

One real failure: the home screen widget's *approaching* amber at 3.24:1
against its background. That clears the 3:1 bar for large text and UI
components, but the status line is 13sp — normal text, needing 4.5:1.
Corrected to #8A5E0A, at 4.91:1.

Everything else passed. Every `IconButton` already carried a `tooltip`, which
is what TalkBack reads, and `BudgetBar` already wrapped its progress bar in
`Semantics` with the same sentence a sighted user sees — a progress bar
otherwise announces a bare percentage, which is not what anyone wants to hear.

`Image.file` was the remaining gap. An unlabelled image is skipped **silently**
by a screen reader rather than announced as unlabelled, so a blind user had no
way to know a receipt was attached at all.
