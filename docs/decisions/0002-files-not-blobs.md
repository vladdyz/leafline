# 0002 — Receipt photos are files on disk, not database blobs

**Status:** accepted, 2026-09-17

## Context

Each expense may carry one receipt photo, roughly 250–350 KB as a downscaled
JPEG. SQLite can store these as BLOBs in the expenses table.

## Decision

Write photos to the app's documents directory as `<uuid>.jpg`. Store only the
**filename** in `expenses.photo_file`.

## Alternatives

- **BLOBs in the expenses table.** A few hundred receipts becomes a database
  of hundreds of megabytes. Every query against that table pays for it, even
  queries that never touch the photo column.
- **Storing the absolute path.** The documents directory moves across
  reinstalls and some OS upgrades. An absolute path saved today can be a dead
  pointer tomorrow; a filename resolved against the current directory is not.

## Consequences

- The database stays small and fast regardless of photo count.
- Two things can now be out of sync: a row pointing at a missing file, and a
  file with no row. Both are handled — a missing file renders a placeholder
  and leaves the expense usable, and an orphan sweep on startup deletes
  files with no matching row.
- Photo retention becomes possible (see 0006). The expense outlives its
  photo, which would be awkward if the photo were a column of the expense.
