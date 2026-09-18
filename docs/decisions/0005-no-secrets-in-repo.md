# 0005 — Signing keys never enter the repository

**Status:** accepted, 2026-09-17

## Context

Release builds need a keystore. The path of least resistance is committing
`key.properties` and the `.jks` file so builds work everywhere.

## Decision

`android/key.properties`, `*.jks` and `*.keystore` are in `.gitignore` from
the first commit. CI reads signing material from repository secrets.

## Alternatives

- **Commit them and make the repo private.** Repos change visibility, get
  forked, and get shared with recruiters. A committed key is in the history
  forever, and rotating an Android signing key means users cannot upgrade —
  they have to uninstall and lose their data.

## Consequences

- Release builds need local setup that is documented in the README rather
  than being automatic.
- Keep a backup of the keystore somewhere outside the repo. Losing it has the
  same consequence as leaking it.
- The ignore rules are in place before there is anything to ignore, which is
  the only time this is easy to get right.
