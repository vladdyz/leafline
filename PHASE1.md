# Phase 1 — Data layer

Overlay these files onto your existing `canopy` project, preserving paths.

## 1. Add the test-only dependency

```bash
flutter pub add --dev sqflite_common_ffi
```

`flutter test` runs on the Dart VM, where the normal sqflite plugin has no
platform to talk to. This gives tests a real SQLite through FFI. See
`docs/decisions/0008-ffi-for-repository-tests.md`.

## 2. Files in this overlay

```
lib/models/expense.dart              Expense: map conversion, copyWith, equality
lib/models/budget.dart               Budget: the single weekly row
lib/data/database.dart               Schema, version, migration ladder
lib/data/expense_repository.dart     CRUD, date ranges, week aggregation
lib/data/budget_repository.dart      Read/write the singleton
lib/data/image_store.dart            Receipt files on disk, orphan sweep
test/helpers/test_database.dart      In-memory DB + fixture builder
test/models/expense_test.dart        Model tests
test/data/repository_test.dart       Repository tests against real SQLite
test/data/image_store_test.dart      File store tests against a temp dir
docs/decisions/0008-*.md             Why FFI for repository tests
docs/decisions/0009-*.md             Why a change stream, not reactive queries
analysis_options.yaml                REPLACES Phase 0's — see below
.github/workflows/ci.yml             REPLACES Phase 0's — adds libsqlite3
```

Two files replace their Phase 0 versions rather than adding to them.

**`analysis_options.yaml`** drops `always_use_package_imports`. Test helpers
live outside `lib/`, so `package:` URIs cannot reach them and a relative
import is the only option. `avoid_relative_lib_imports` stays, and it catches
the genuinely dangerous case: reaching *into* `lib/` from outside, which
creates a duplicate library.

**`.github/workflows/ci.yml`** installs `libsqlite3-dev`. Without it the
repository tests fail at `open()` with a library-not-found error that reads
nothing like a database problem.

## 3. Delete the placeholder READMEs

```bash
rm lib/models/README.md lib/data/README.md
```

## 4. Verify

```bash
flutter analyze --fatal-infos
dart format .
flutter test
```

Roughly 90 tests total once Phase 0's are included.

## What is NOT here

- No `path_provider` call. `ImageStore` takes a `Directory`, which is what
  makes it testable without a plugin channel. Phase 2 wires the real
  documents directory in at the provider level.
- No Riverpod providers. Phase 2 adds those alongside the UI that needs them.
- No UI at all. The entire phase is verifiable with `flutter test`; you will
  not need the phone again until Phase 2.

## Deviation from the design doc

The doc's schema sketch defaulted `category` to `'uncategorized'`. The code
uses `'custom'`, matching `ExpenseCategory.custom.id` — a default that does
not correspond to a real enum value would silently become one on the first
`fromId` lookup anyway.
