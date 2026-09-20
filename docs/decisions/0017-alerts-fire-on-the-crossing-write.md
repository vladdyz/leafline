# 0017 — A warning fires on the write that crosses the line

**Status:** accepted, 2026-09-20

## Context

Two budget warnings exist: one at 80% of the week, one when the budget is
passed. Something has to decide when they fire.

## Decision

`BudgetAlertService.checkAndNotify` runs **after an expense is written**, and
nowhere else. The week each alert last fired in is stored, and an alert whose
stored week matches the current one does not fire again.

## What does not trigger a check

- **Deleting an expense.** Spending goes down. There is nothing to warn about.
- **Changing a budget.** Someone in Settings choosing a smaller number already
  knows what they have done, and a system notification about the screen you
  are looking at is noise.
- **Opening the app.** A warning on launch is about a line you crossed at some
  point in the past, which is exactly the signal that teaches people to
  disable notifications.

The write is the moment the total changes in the direction that matters. That
is the only moment worth interrupting someone for.

## Once per week, and how it resets

Each alert stores the Monday of the week it fired in. Firing again requires
the stored week to differ from the current one, which happens on its own every
Monday — no scheduled job, no cleanup, no counter to zero.

This is the rule the whole feature depends on. Warning on every expense past
the 80% mark turns a useful signal into nagging; a nagging app gets its
notifications switched off within a week, and then none of the warnings work.

## Recording before showing

The fired week is written **before** the notification is shown, so a refused
permission still counts as fired. The alternative asks again on the very next
expense, which is how a permission prompt becomes the thing being dismissed.

A warning that silently fails is better than one that fires twice.

## Crossing straight past

An expense that jumps from under 80% to over the budget records **both**
thresholds. Otherwise deleting back into the 80-99% band would produce a
"getting close" warning about a limit already crossed once — the app saying
something it has already said louder.

## One notification id

Both alerts use the same id, so the second replaces the first rather than
stacking beside it. Two warnings about the same week on screen at once is the
app talking over itself.
