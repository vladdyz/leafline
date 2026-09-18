# 0001 — Money is stored as integer cents

**Status:** accepted, 2026-09-17

## Context

Every amount in this app is currency: expense amounts, weekly totals, budget
thresholds. Dart's `double` is an IEEE 754 binary float and cannot represent
most decimal fractions exactly. `0.1 + 0.2` is `0.30000000000000004`.

Summing a week of expenses stored as doubles produces totals that are off by
a cent, intermittently, in a way that depends on the order of addition.

## Decision

Store and compute every amount as `int` cents. Parse at the input edge
(`parseAmountToCents`), format at the display edge (`formatCents`), and never
let a `double` exist in between.

The one exception is `budgetProgress`, which returns a `double` because
`LinearProgressIndicator` requires one. It is a display value only and is
never summed or stored.

## Alternatives

- **`double` with rounding at display time.** Rounding hides the error rather
  than preventing it, and errors still accumulate across a sum.
- **A `Decimal` package.** Correct, but adds a dependency and a type that has
  to be serialised in and out of SQLite. Integer cents needs neither.

## Consequences

- SQLite stores `amount_cents INTEGER`, which it handles natively.
- Percentage comparisons use integer arithmetic where possible
  (`spentCents >= budgetCents * 0.8` is the one float comparison, and it is a
  threshold test, not an accumulation).
- Parsing must be explicit about what it accepts. `parseAmountToCents`
  returns `null` rather than guessing, and its test suite is the record of
  what counts as valid input.
