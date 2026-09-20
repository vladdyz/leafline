# 0018 — The app lock is off by default, and the device PIN always works

**Status:** accepted, 2026-09-20

## Context

Receipt photos show where you go, when, and what you buy. Decision 0004 said
no accounts, because a local password protects nothing — the database sits in
the app's sandbox either way, and anyone who can read the file has already
gone around any check the app makes.

That left exactly one real threat from the threat model: **someone picking up
your unlocked phone.**

## Decision

An optional lock, using the device's own authentication. Off by default.
Biometric *or* device PIN — never biometric only.

## Off by default

This guards one threat, and not everyone has it. Someone who lives alone and
never hands their phone over gains an unlock step and nothing else. Defaulting
it on would make the app feel like it holds something more dangerous than a
list of coffees.

It is offered where the reason for it is visible: under a Privacy heading that
says what a receipt reveals.

## `biometricOnly: false`

The most important line in the service.

A biometric-only lock locks people out of their own data the first time a wet
thumb, a cracked sensor or a re-enrolled face stops cooperating — and with no
account and no backend, there is no recovery path whatsoever. The device PIN
is always an acceptable answer.

## The two-minute grace window

Locking on every resume sounds more secure and is worse. Glancing at a
notification and coming back would re-prompt, which trains people to switch
the lock off — and a lock that is off protects nothing.

Two minutes covers the interruption case and not much else. Cold start always
locks, regardless.

## The child stays built

The lock screen covers the app rather than replacing it, so unlocking returns
to exactly where the user was. It shows no figures, no merchant names and no
thumbnails — not even blurred, since a blur that survives a screenshot is
decoration rather than a lock.
