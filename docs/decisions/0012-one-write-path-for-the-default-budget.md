# 0012 — BudgetRepository is removed; one write path for the default

**Status:** accepted, 2026-09-18

## Context

Phase 1 gave the standing budget its own `BudgetRepository`. Phase 2.5 gave
`WeekBudgetRepository` the same two operations, because writing the default
now has a consequence: the current week follows it, unless that week has been
overridden.

That left two classes able to write the same row, one of which enforced the
rule and one of which did not.

## Decision

`BudgetRepository` is deleted. `WeekBudgetRepository.getDefault` and
`setDefaultWeeklyCents` are the only way to read or write it.

## Why not keep both

Because the broken path is the more obvious one. `BudgetRepository.setWeeklyCents`
does exactly what its name says and leaves the current week stale — no error,
no warning, just a week running on a budget the user thinks they changed. A
future call site would reach for it precisely because the name looks right.

Two write paths where one silently skips an invariant is not a redundancy. It
is a trap with a plausible name on it.

## Consequences

- One import fewer, and one fewer class to keep in sync.
- The Phase 1 `BudgetRepository` test group is deleted rather than migrated:
  `week_budget_repository_test.dart` already covers reading and writing the
  default, and covers the rule the old class could not.
- The settings screen writes through the week repository, with a comment
  saying why, because "settings writes to the *week* repository" is the sort
  of thing that looks like a mistake until you know.
