# 0004 — No user accounts in v1

**Status:** accepted, 2026-09-17

## Context

Expense data feels sensitive, which creates an instinct to put a login in
front of it.

## Decision

No accounts, no login, no password. The app is single-user, on-device, and
makes no network calls.

## Alternatives

- **A local PIN or password check.** This protects nothing. The data sits in
  the app's sandbox either way, and anyone able to read the database file has
  already bypassed the check. It is the appearance of security.
- **Full auth with a backend.** A real project — see the sync section of the
  design doc — but a different one, and not a prerequisite for tracking your
  own spending.

## Consequences

- Nothing to authenticate against, so no auth code, no token storage, no
  session handling, no password reset.
- The realistic threats are someone picking up an unlocked phone, and photos
  leaking into the gallery. Both are addressed directly: an optional
  biometric lock in Phase 4, and writing to the documents directory rather
  than external storage.
- Device-level encryption already covers a lost or stolen phone.
- If sync is added later, this decision is revisited in full. It is not an
  extension of the current design; it is a new one.
