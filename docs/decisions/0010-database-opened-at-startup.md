# 0010 — The database is opened at startup, not lazily

**Status:** accepted, 2026-09-18

## Context

`AppDatabase.open` is asynchronous. Riverpod offers an obvious way to model
that: a `FutureProvider<AppDatabase>` that every repository provider watches.

## Decision

`main()` opens the database and resolves the documents directory before
`runApp`, then supplies both through `ProviderScope` overrides. The providers
that hold them have no default and throw if used un-overridden.

## Alternatives

- **`FutureProvider<AppDatabase>`.** Because a provider watching a
  `FutureProvider` is itself asynchronous, this makes the repository providers
  async, which makes every provider built on them async, which means screens
  unwrap an `AsyncValue` for "is the database open" on top of the one they
  already unwrap for their actual query. Nested `AsyncValue` handling spreads
  through the whole UI to model a condition that is true for a few
  milliseconds at launch and never again.

## Consequences

- Repository providers are plain `Provider`s and return their object directly.
- Screens use `AsyncValue` only where something is genuinely asynchronous —
  running a query.
- Startup blocks on the database open. It is a local file; this is
  milliseconds, and the alternative is a loading state on every screen.
- Tests override the same two providers with an in-memory database and a temp
  directory, so a widget test runs against real repositories and real SQL
  rather than mocks.
- The un-overridden providers throw. That is a programming error, not a
  runtime condition, and the message names the fix.
