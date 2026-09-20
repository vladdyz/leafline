import 'package:receipt_tracker/models/ocr_block.dart';
import 'package:receipt_tracker/services/ocr_service.dart';

/// An [OcrService] that answers from memory.
///
/// Every state the form has to cope with is reachable from here: a readable
/// receipt, an unreadable one, a platform with no OCR, and a channel that
/// fails. The form should render the same thing for three of those four.
class FakeOcrService implements OcrService {
  FakeOcrService({
    this.available = true,
    this.blocks = stubReceiptBlocks,
    this.failure,
  });

  /// Reports nothing legible, as a photo of a blank wall would.
  factory FakeOcrService.findsNothing() =>
      FakeOcrService(blocks: const <OcrBlock>[]);

  /// Reports a platform with no implementation.
  factory FakeOcrService.unavailable() => FakeOcrService(available: false);

  /// Reports a channel that could not be reached.
  factory FakeOcrService.fails() => FakeOcrService(
    failure: const OcrFailure(
      OcrFailureKind.unknown,
      'No OCR plugin is registered',
    ),
  );

  final bool available;
  final List<OcrBlock> blocks;
  final OcrFailure? failure;

  /// Paths this service was asked about, in order.
  final List<String> calls = <String>[];

  @override
  bool get isAvailable => available;

  @override
  Future<List<OcrBlock>> recognize(String path) async {
    calls.add(path);
    final f = failure;
    if (f != null) throw f;
    return blocks;
  }
}
