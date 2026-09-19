# 0011 — A week exists because it has a budget, not because it has expenses

**Status:** accepted, 2026-09-18

## Context

Through Phase 2 the week list was built by grouping expenses. A week existed
because something was spent in it. That produced three failures, and they
compound:

1. **A perfect week is invisible.** Set a budget, spend nothing, and the week
   does not appear. The best outcome the app exists to encourage is the one
   outcome it cannot display.
2. **Monday morning shows nothing.** The current week has no expenses yet, so
   there is no current week — no budget, no bar, no sense that the app is
   running.
3. **History cannot be drawn.** A calendar of weeks needs to know which weeks
   the user was tracking. Grouping by expenses cannot answer that: a week with
   no expenses is indistinguishable from a week before the app was installed,
   so either every week back to the start of the calendar renders as a
   flawless week the user never lived, or genuine zero-spend weeks are
   discarded along with them.

The third is the one that forces the decision. Any history view is wrong
without a record of when tracking started.

## Decision

A `week_budgets` table, one row per week, keyed by the Monday. The presence of
a row is what makes a week exist.

Rows are created — *materialised* — on app start for the current week, and
when an expense is written into a week that has none. A row copies the
standing default budget at that moment and keeps it.

## The rules that follow

- A row with no expenses is a tracked week where nothing was spent. It renders
  in full, and it counts as a success.
- No row means the week was never tracked. Not a success, not a failure — the
  app was not in use, and it says so.
- Changing the default never reaches into a completed week.
- The current week is the one exception: while it is running, and only if the
  user has not overridden it, it follows the default. Mid-week is not history
  yet.
- An overridden week ignores the default entirely. Set the vacation week to
  $500 and the week after still starts from the standing $100.

## Alternatives

- **Derive the week's budget from a dated budget-history table.** More
  faithful in principle, and it answers "what was the budget on this date"
  for any date. But it still cannot answer "was the user tracking", which is
  the actual question, and it needs range queries where this needs a primary
  key lookup.
- **Materialise every week between the last tracked week and today on open.**
  Fills gaps automatically, and lies: a week the user never opened the app
  becomes a week they stayed under budget. Gaps stay untracked.
- **Store the outcome per week.** Denormalises something cheap to compute and
  creates a second source of truth that can drift from the expenses.

## Consequences

- Schema version 2. The migration creates the table and backfills a row for
  every week that already contains an expense, at the current default — the
  best available answer for weeks that predate the concept.
- "Untracked" becomes a real state the UI has to render, distinct from "spent
  nothing".
- `WeekOutcome` has four states rather than two, and deliberately has no
  "approaching": that is a live warning meant to change what you do next, and
  a week that finished at 85% was a success, not a near-miss.
- A week's budget is frozen by nothing more than never being written again.
  No scheduler, no rollover job, no background work.
