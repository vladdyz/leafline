# 0007 — Local notifications only; no SMS or email

**Status:** accepted, 2026-09-17

## Context

Budget warnings need to reach the user when the app is closed. SMS and email
were considered.

## Decision

`flutter_local_notifications` only. No server, no gateway, no stored contact
details.

## Alternatives

- **SMS via a gateway such as Twilio.** Requires a backend, a paid account,
  the user's phone number stored somewhere, and a consent and opt-out flow —
  all to deliver a message to the phone already in their hand.
- **Email.** Same backend requirement, plus deliverability problems, to reach
  an inbox slower than a notification reaches the lock screen.

## Consequences

- No cost, no backend, no data leaving the device.
- Android 13+ needs the `POST_NOTIFICATIONS` runtime permission, requested at
  the point the first notification would fire.
- Each threshold fires at most **once per week**. This is the rule the
  feature depends on: notifying on every expense past the 80% mark turns a
  useful signal into nagging, the user disables notifications, and then none
  of the alerts work at all.
- The weekly summary uses an inexact scheduled notification. Exact alarms are
  restricted on Android 12+ and a Monday summary does not need the precision.
