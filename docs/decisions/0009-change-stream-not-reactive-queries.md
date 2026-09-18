# 0009 — A bare change stream instead of reactive queries

**Status:** accepted, 2026-09-18

## Context

The week list needs to refresh when an expense is added, edited or deleted.
sqflite has no reactive query support — it returns futures, not streams that
re-emit when underlying data changes.

## Decision

Each repository exposes `Stream<void> get changes`, a broadcast stream that
emits after any write that actually changed a row. Listeners re-run whatever
query they care about.

## Alternatives

- **Switch to `drift`**, which has genuine reactive queries and compile-time
  checked SQL. A good library, and the right answer for a larger app. It also
  replaces the hand-written schema with generated code, which would remove
  most of what makes this project a useful exercise in SQL and migrations.
- **Build query-level observability over sqflite** — track which tables each
  query touches and re-emit selectively. That is re-implementing drift badly.
- **Nothing; refresh from the view model after each write.** Works, but
  couples every caller to remembering to do it, and gets missed exactly once,
  in the place that matters.

## Consequences

- The repository does not know who is listening or what they query. It says
  only "something changed."
- Refreshes are coarse: any write re-runs every listening query. At this data
  volume that is free, and it is trivially correct, which a selective scheme
  would not be.
- Writes that change nothing — updating an unknown id, deleting a row that is
  already gone — do not emit. That keeps a no-op from triggering a rebuild.
- Repositories own a `StreamController` and therefore need disposing. Tests
  do this in `tearDown`; Riverpod will do it via `ref.onDispose` in Phase 2.
