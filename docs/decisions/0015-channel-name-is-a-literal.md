# 0015 — The channel name is a plain literal on both sides

**Status:** accepted, 2026-09-20

## Context

A `MethodChannel` is identified by a string that must be byte-identical in
Dart and in Kotlin. The Flutter convention is a reverse-domain prefix, and the
obvious way to produce one is to derive it from the package name.

## Decision

`receipt_tracker/ocr`, written out as a literal in both
`ChannelOcrService.channelName` and `OcrPlugin.CHANNEL`. It is not derived
from anything.

## Why

A channel name only has to be unique within one app. Deriving it from the
package buys nothing and costs something: change your `--org`, or generate the
project twice, and the two sides drift apart.

The failure mode is what makes this worth a decision record. A mismatched
channel does not report a mismatch — it reports `MissingPluginException`,
which reads as *the plugin was never registered*. You then go and check
`MainActivity`, find the registration present and correct, and start looking
for the problem somewhere it isn't.

Two literals can be diffed. A unit test does exactly that.

## Consequences

- The name carries no package information, which is fine: nothing needs it to.
- `ChannelOcrService` catches `MissingPluginException` and rethrows an
  `OcrFailure` whose message names the channel and points at `MainActivity` —
  so if it does happen, the error says where to look.
- A test asserts the Dart constant's value. It cannot read the Kotlin, so it
  pins one side against a literal that a human compared once.
