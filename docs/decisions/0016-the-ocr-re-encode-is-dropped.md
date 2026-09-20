# 0016 — The post-OCR re-encode is dropped

**Status:** accepted, 2026-09-20. Supersedes a step in the Phase 3 plan.

## Context

The design called for photos to be captured at 1600px/quality 80 — enough
resolution for text recognition — and then re-encoded to 1200px/quality 70
once OCR had finished, since a human reading the receipt back later needs far
less. That roughly halves a stored photo, from about 300KB to about 150KB.

It was deferred out of Phase 3b and again out of 3d, on the grounds that it is
an optimisation rather than a feature.

## Decision

Dropped, not deferred again.

## Why

The justification was unbounded growth. At fifteen receipts a week, photos
reached roughly 230MB a year and kept going; halving that mattered because the
number had no ceiling.

Retention puts a ceiling on it. At the three-month default the library holds
about 195 photos — call it 57MB — and stays there. Halving 57MB is not worth
what it costs.

And it costs more than it looks. Dart cannot re-encode a JPEG without a
package: either `image`, which is pure Dart and takes a second or two per
photo on a phone, or `flutter_image_compress`, which is native and therefore a
platform channel — meaning another interface, another fake, and another set of
widget tests that cannot touch it. That is a real amount of surface area for
30MB.

## Alternatives

- **Capture at a lower resolution.** Cheapest of all, and wrong: the
  resolution is what recognition needs. It is only surplus afterwards.
- **Re-encode lazily, during the retention sweep.** Compresses photos on
  their way to being deleted anyway. All of the cost, almost none of the
  benefit.

## Consequences

- One fewer dependency, and no image codec in the app.
- Photos stay at capture quality for as long as they are kept, which is
  slightly better for reading one back than the plan called for.
- If retention is ever set to "forever" by a heavy user, growth is unbounded
  again and this decision is worth revisiting. Settings shows the running
  total precisely so that becomes visible rather than surprising.
