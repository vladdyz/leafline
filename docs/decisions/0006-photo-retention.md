# 0006 — Photos expire; expenses do not

**Status:** accepted, 2026-09-17

## Context

Receipt photos accumulate. At fifteen receipts a week they reach roughly
230 MB a year, which is unremarkable at first and an annoyance by year three.
When a phone runs low on storage, Android prompts the user to clear app data
— and clearing app data takes the database with it.

## Decision

A retention setting with options of 1 month, 3 months, 1 year, or forever,
defaulting to 3 months. A sweep on app startup deletes expired photo files and
sets `photo_file` to `NULL` on the affected rows.

The expense row, its amount, its category and its `ocr_raw_text` are never
touched.

## Alternatives

- **Keep everything forever.** Works until it doesn't, and the failure mode
  is the user clearing app data.
- **Delete the whole expense when its photo expires.** Destroys the spending
  history, which is the actual product.
- **A storage cap that deletes oldest-first.** More complex, and a
  time-based rule is easier for a user to reason about than a size-based one.

## Consequences

- Spending history is permanent; images are a temporary convenience.
- The UI needs a "photo expired" state distinct from "photo missing due to
  error", though both render the same neutral placeholder.
- Re-encoding after OCR (1200px, quality 70) roughly halves the accumulation
  rate, which makes the default retention window comfortable rather than
  tight.
- Settings shows current photo count and total MB, so the number is visible
  before it becomes a problem.
