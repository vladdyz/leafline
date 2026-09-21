# 0019 — The home screen widget renders a snapshot, not a query

**Status:** accepted, 2026-09-21

## Context

An app widget runs in the launcher's process, on Android's schedule, with no
Flutter engine attached. It has to get the week's figures from somewhere.

## Decision

Dart pushes a small set of **finished strings** into SharedPreferences through
a MethodChannel whenever the current week changes. The widget reads those and
draws them. It never opens the database and never computes anything.

## Why not query the database

Two processes opening the same SQLite file to render one number is
lock contention bought for nothing — and it would put the schema in two places,
so every migration would need a matching change in Kotlin or the widget would
silently show stale or wrong figures.

## Why strings rather than cents

Money formatting lives in `formatCents`, and the week label in `week_math`.
Sending cents would mean reimplementing both in Kotlin, and two
implementations of a money format is one more than can be kept in agreement.
The first divergence would be a thousands separator nobody notices for months.

`percent` is the single exception: a `ProgressBar` needs an integer, and the
clamp to 0–100 is a display rule rather than a formatting one. A week at 340%
fills the bar; handed 340, a `ProgressBar` renders undefined.

## Why listen rather than push from each write

`main.dart` listens to `currentWeekProvider`. Every route that changes the
week — adding an expense, deleting one, changing a budget, the Monday
rollover — already flows through it, so none of them has to remember to push.

Calling the bridge from each write path would work until someone added a
sixth write path and forgot.

## Consequences

- The widget is a convenience surface; the app is the source of truth. A
  widget that failed to redraw is not worth an error, and the bridge swallows
  channel failures deliberately.
- Before the app has ever run, the layout's own defaults show — "Open
  LeafLine" rather than zeroes, which would look like a real figure.
- The widget cannot show anything the app has not computed. Adding a field to
  it means adding it to `WidgetSnapshot`, which is the right amount of
  friction.
