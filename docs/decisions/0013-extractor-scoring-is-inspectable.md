# 0013 — The extractor records why it scored what it did

**Status:** accepted, 2026-09-19

## Context

`TotalExtractor` ranks the amounts on a receipt by summing weighted signals:
a total label, a subtotal label, tax and tender words, position on the
receipt, magnitude. It will be wrong on some receipts, and the only way to
improve it is to understand why it was wrong on a particular one.

## Decision

Every `AmountCandidate` carries a `reasons` list naming the signals that
produced its score, and the `sourceLine` it came from. Every weight is a named
constant on `TotalExtractor`.

## Alternatives

- **Return bare amounts.** Smaller, and leaves you staring at a wrong number
  with no way to tell whether it beat the right one because of position,
  magnitude, or a label that matched something unintended.
- **Log the scoring.** Same information, available only when you happen to be
  watching, and absent from test failures — which is exactly where it is most
  useful.

## Consequences

- A failing fixture prints the full score breakdown for every candidate, so
  the fix is a weight change rather than an investigation.
- `reasons` is never shown in the UI. It exists for the developer.
- The weights are tunable in one place, which matters because they will be
  tuned — the fixture suite is the record of that tuning.
- `ocr_raw_text` is stored on every expense (decision 0002 kept it), so a
  receipt that fools the extractor in real use can be turned into a fixture
  without re-photographing anything.
