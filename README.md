# Receipt Tracker

A weekly expense tracker for Android. Log small spending by hand or by
photographing a receipt, see it grouped by week, and get warned as the weekly
total approaches a budget.

Built with Flutter for the UI and Kotlin for the Android platform work, with a
`MethodChannel` between them.

> **Status: Phase 0.** Skeleton, utility layer, and CI. The screen you see on
> launch is a placeholder with hardcoded figures.

## What it is for

Discretionary spending that accumulates unnoticed — transit fares, coffee,
lunches out, small shopping. Fixed monthly obligations such as rent and car
payments are deliberately out of scope: they are known and already budgeted,
and including them would swamp the weekly number the app exists to surface.

## Why Flutter and Kotlin together

They share no code. That is the point.

Flutter handles the UI, state and local persistence. Kotlin handles the parts
Flutter cannot reach: on-device text recognition through ML Kit, and later a
home screen widget, which cannot be written in Dart at all. The boundary
between them is one channel with one method, documented below.

```
Screens (Flutter widgets)
  └── View models (Riverpod)
        ├── Repositories ──┬── sqflite
        │                  └── File store (app documents dir)
        └── OcrService ──[MethodChannel]── OcrPlugin (Kotlin) ── ML Kit
```

Each layer talks only to the one below it. Widgets never touch sqflite;
repositories never import Flutter.

## Setup

Requires the Flutter SDK on `PATH` and an Android SDK.

```bash
./scripts/setup.sh com.yourdomain
```

This creates the Flutter scaffold, adds dependencies at their current
versions, overlays the files from this skeleton, places the Kotlin OCR stub at
the right package path, and runs the checks.

Dependencies are added by the script rather than pinned in a checked-in
`pubspec.yaml` on purpose — pinned versions go stale, and day one of a project
is exactly when you want current ones.

## Running

```bash
flutter run                 # debug build on a connected device
flutter build apk --debug   # debug APK
```

## Testing

```bash
flutter test                          # unit and widget tests
flutter test --coverage               # with an lcov report
cd android && ./gradlew testDebugUnitTest   # Kotlin unit tests
```

CI runs all of these on every push, plus `flutter analyze --fatal-infos` and a
formatting check.

## Project layout

```
lib/
  models/      Expense, Budget                         (Phase 1)
  data/        Repositories, database, image store     (Phase 1)
  services/    OCR channel, total extractor            (Phase 3)
  state/       Riverpod providers                      (Phase 2)
  ui/          Screens and widgets                     (Phase 2)
  util/        Money, week math, budget rules          (Phase 0)
android/app/src/main/kotlin/<pkg>/
  ocr/         OcrPlugin, ReceiptTextMapper            (Phase 0 stub)
```

## The channel contract

Channel: `<org>.receipt_tracker/ocr`

| Method | Argument | Success | Errors |
| --- | --- | --- | --- |
| `recognizeText` | `{ "path": String }` | `List<Map>` with `text`, `left`, `top`, `width`, `height` | `FILE_NOT_FOUND`, `DECODE_FAILED`, `RECOGNITION_FAILED` |

Kotlin returns recognised text and nothing more. Deciding which number on a
receipt is the total happens in Dart (`TotalExtractor`), where it can be unit
tested against fixture strings without a device.

**The Phase 0 stub returns hardcoded blocks without calling ML Kit.** Get that
round trip working before adding real recognition — the channel and the
recognition library are two things that can each break, and debugging them
together is much harder than debugging them apart.

## Known limitations

- **Android only.** The native half is Android-specific by design.
- **Total extraction is heuristic.** It ranks candidates by proximity to the
  word "total", position on the receipt, and magnitude, penalising lines that
  look like subtotals, tax or change. It will be wrong on some receipts, so
  the UI offers candidates as tappable chips rather than auto-filling. A wrong
  guess costs one tap.
- **Photos expire by default after 3 months**, configurable. The expense,
  its amount and its recognised text are kept permanently; only the image is
  removed. See `docs/decisions/0006-photo-retention.md`.
- **No sync, no accounts, no backup.** Data lives on one device. Adding sync
  is a separate project, not an extension of this one.
- **One photo per expense**, and it is optional — most small expenses have no
  receipt worth keeping.
- **One currency**, no multi-currency support.

## Design decisions

Short records in `docs/decisions/`, one per choice, written the day the
decision was made:

| | |
| --- | --- |
| 0001 | Money is stored as integer cents |
| 0002 | Receipt photos are files on disk, not database blobs |
| 0003 | Total extraction lives in Dart, not Kotlin |
| 0004 | No user accounts in v1 |
| 0005 | Signing keys never enter the repository |
| 0006 | Photos expire; expenses do not |
| 0007 | Local notifications only; no SMS or email |

The full system design — schema, sequence diagrams, threat model, phase plan,
test matrix — lives in the design document this repository was built from.

## Roadmap

| Phase | Delivers | Status |
| --- | --- | --- |
| 0 | Skeleton, utils, CI | Done |
| 1 | Data layer with tests, no UI | |
| 2 | Manual entry, week list, budget bar | |
| 3 | Camera, Kotlin OCR channel, amount picker | |
| 4 | Polish, retention, notifications, device lock | |
| 5 | Home screen widget | |

Phase 2 is already a usable app. Everything after it is addition, not
completion.
