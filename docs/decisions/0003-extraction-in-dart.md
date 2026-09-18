# 0003 — Total extraction lives in Dart, not Kotlin

**Status:** accepted, 2026-09-17

## Context

ML Kit runs on Android and is reached over a MethodChannel. Having recognised
a receipt, something has to decide which of the numbers on it is the total.
That logic could sit on either side of the channel.

## Decision

Kotlin returns raw recognised text blocks with their bounding boxes and makes
no judgement about meaning. `TotalExtractor`, in Dart, ranks candidate
amounts.

## Alternatives

- **Extract in Kotlin, return one amount.** Puts the most-likely-to-change,
  most-likely-to-be-wrong logic on the side that needs an emulator to test and
  a channel round trip to exercise.

## Consequences

- The channel contract stays trivial: a path in, text and boxes out. A
  trivial contract is one that rarely needs to change.
- The heuristic is a pure function over strings, testable against a fixture
  folder with no device, no plugin, and no async.
- Every receipt that fools the extractor becomes a permanent regression test.
  The suite improves precisely when the heuristic fails, which is the right
  feedback loop for something that will never be perfect.
