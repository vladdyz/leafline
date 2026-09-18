# lib/services

Phase 3. Platform boundaries and pure logic that sits behind them.

- `ocr_service.dart` — Dart side of the MethodChannel, typed results
- `total_extractor.dart` — ranks candidate totals from recognised text
- `notification_service.dart` — Phase 4, local notifications

`total_extractor.dart` is pure Dart on purpose. Kotlin returns raw text;
deciding what that text means is logic, and logic belongs where it is
cheapest to unit test.
