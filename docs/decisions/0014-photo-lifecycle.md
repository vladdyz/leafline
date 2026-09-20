# 0014 — The expense id is generated when the form opens

**Status:** accepted, 2026-09-19

## Context

A receipt photo is filed under its expense's id — `<uuid>.jpg` — so that the
mapping between a row and a file is obvious when inspecting the directory by
hand (decision 0002).

But the photo is taken *while the form is open*, and the row does not exist
until the user hits save. There is nothing to name the file after yet.

## Decision

`ExpenseFormScreen` generates the uuid in `initState` for a new expense and
holds it in `_id`. The photo is written under that id immediately; saving
uses the same id for the row.

## Alternatives

- **Save to a temp name, rename on save.** Two filesystem operations instead
  of one, a second failure point, and a window where the name means nothing.
- **Hold the bytes in memory until save.** A form holding several megabytes
  is a form that loses the photo when Android reclaims the process — which is
  precisely when someone is fumbling with a receipt at a till.

## Consequences

- **Abandoning a form leaves an orphan file.** Deliberately accepted: the
  startup sweep already exists for it, and losing a photo is worse than
  briefly keeping one nobody wants.
- Photo capture works identically for a new expense and an edit, because both
  have an id by the time the camera opens.

---

# Photos outlive the expenses that reference them

A related decision, recorded here because the reasoning is the same shape.

Deleting an expense does **not** delete its photo. The design sketch said it
should, and that is wrong once undo exists: swipe to delete, tap Undo, and the
row comes back pointing at a file that has already gone.

So expense deletion removes only the row. The photo becomes an orphan and the
startup sweep collects it, by which time undo is long past.

Removing a photo from the form is the exception and deletes the file
immediately — there is nothing to undo, and the user asked directly.
