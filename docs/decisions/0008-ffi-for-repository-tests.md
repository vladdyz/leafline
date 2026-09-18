# 0008 — Repository tests run against real SQLite via FFI

**Status:** accepted, 2026-09-18

## Context

`flutter test` executes on the Dart VM, not on a device or emulator. The
normal `sqflite` plugin is a platform channel with no platform on the other
end there, so any test that opens a database fails immediately.

The data layer is the part of this app most worth testing — date ranges,
aggregation, constraint behaviour — and all of it is SQL.

## Decision

Add `sqflite_common_ffi` as a dev dependency. Tests call `sqfliteFfiInit()`
once, then open `inMemoryDatabasePath` through `databaseFactoryFfi`.
`AppDatabase.open` takes an optional `DatabaseFactory` so production code
passes nothing and gets the platform default.

## Alternatives

- **Mock the database.** Would test that the repository calls the methods we
  told it to call, and nothing about whether the SQL is correct. The bugs
  worth catching here are in the SQL: an inclusive bound that should be
  exclusive, a `SUM` over no rows returning `NULL`, a `CHECK` that does not
  fire. A mock catches none of them.
- **Run them as integration tests on a device.** Slow, needs hardware, and
  turns a sub-second feedback loop into a minute-long one.

## Consequences

- The queries under test are executed by real SQLite — the same engine that
  runs on the phone, not an approximation of it.
- Each test opens its own in-memory database, so no state leaks between them
  and no cleanup is needed beyond closing.
- CI on Linux needs `libsqlite3-dev` installed. Without it, `open()` fails
  with a library-not-found error that reads nothing like a database problem.
- `AppDatabase.open` carries an injectable factory parameter that production
  never uses. That is the cost, and it is one line.
