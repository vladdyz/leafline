# lib/data

Phase 1. Repositories and the sqflite database.

- `database.dart` — opens the DB, runs `onCreate` / `onUpgrade`
- `expense_repository.dart` — CRUD and date-range queries
- `budget_repository.dart` — the single budgets row
- `image_store.dart` — writes, resolves and sweeps receipt files

Nothing in here imports Flutter. That is what makes it testable without a
widget harness.
