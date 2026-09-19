import 'package:receipt_tracker/models/ocr_block.dart';

/// Reads text from a receipt photo.
///
/// An interface rather than a concrete channel wrapper, for three reasons.
///
/// It keeps iOS open: a Swift implementation over Apple's Vision framework
/// satisfies this contract without a line changing above it. It makes the OCR
/// path testable without a device, since a fake implementation is a class
/// rather than a mocked platform channel. And it makes OCR genuinely optional
/// — [isAvailable] lets a platform with no implementation say so, and the form
/// simply does not offer candidate chips.
///
/// That last point is why the whole feature degrades cleanly. Photos are
/// optional and OCR is a convenience on top of them, so an absent
/// implementation costs the user one typed amount, not a broken screen.
abstract interface class OcrService {
  /// Whether this platform can recognise text at all.
  bool get isAvailable;

  /// Recognised blocks for the image at [path].
  ///
  /// Returns an empty list when nothing legible is found — a photo of a
  /// blank wall is an ordinary outcome, not an error. Throws [OcrFailure]
  /// only when recognition could not be attempted.
  Future<List<OcrBlock>> recognize(String path);
}

/// Why recognition could not be attempted.
///
/// The codes mirror the channel contract exactly, so the Kotlin and Dart
/// sides can be read against each other.
enum OcrFailureKind { fileNotFound, decodeFailed, recognitionFailed, unknown }

class OcrFailure implements Exception {
  const OcrFailure(this.kind, [this.message]);

  /// Maps a `PlatformException` code to a kind.
  factory OcrFailure.fromCode(String? code, [String? message]) {
    switch (code) {
      case 'FILE_NOT_FOUND':
        return OcrFailure(OcrFailureKind.fileNotFound, message);
      case 'DECODE_FAILED':
        return OcrFailure(OcrFailureKind.decodeFailed, message);
      case 'RECOGNITION_FAILED':
        return OcrFailure(OcrFailureKind.recognitionFailed, message);
      default:
        return OcrFailure(OcrFailureKind.unknown, message);
    }
  }

  final OcrFailureKind kind;
  final String? message;

  @override
  String toString() =>
      'OcrFailure(${kind.name}${message == null ? '' : ': $message'})';
}

/// The implementation for platforms with no OCR.
///
/// Reports unavailable and returns nothing. Callers need no special case:
/// no blocks means no candidates means no chips, which is the same path a
/// photo of a blank wall takes.
class UnavailableOcrService implements OcrService {
  const UnavailableOcrService();

  @override
  bool get isAvailable => false;

  @override
  Future<List<OcrBlock>> recognize(String path) async => const <OcrBlock>[];
}

/// Returns a fixed receipt, ignoring the path.
///
/// Mirrors the hardcoded blocks in the Kotlin `OcrPlugin` stub, deliberately:
/// the two sides can be compared, and the Dart half of the pipeline can be
/// driven end to end before a channel or ML Kit exists.
///
/// The fake receipt carries the decoys that matter — a subtotal, a tax line,
/// and a cash amount larger than the total — so a pipeline that looks like it
/// works on this data has actually had to rank something.
class StubOcrService implements OcrService {
  const StubOcrService();

  @override
  bool get isAvailable => true;

  @override
  Future<List<OcrBlock>> recognize(String path) async => stubReceiptBlocks;
}

/// The same receipt the Kotlin stub returns.
const List<OcrBlock> stubReceiptBlocks = <OcrBlock>[
  OcrBlock(text: 'CORNER MARKET', left: 40, top: 30, width: 300, height: 40),
  OcrBlock(text: '123 QUEEN ST W', left: 40, top: 80, width: 280, height: 30),
  OcrBlock(
    text: 'COFFEE LARGE      2.75',
    left: 40,
    top: 150,
    width: 400,
    height: 30,
  ),
  OcrBlock(
    text: 'BAGEL             3.50',
    left: 40,
    top: 190,
    width: 400,
    height: 30,
  ),
  OcrBlock(
    text: 'SUBTOTAL          6.25',
    left: 40,
    top: 260,
    width: 400,
    height: 30,
  ),
  OcrBlock(
    text: 'HST 13%           0.81',
    left: 40,
    top: 300,
    width: 400,
    height: 30,
  ),
  OcrBlock(
    text: 'TOTAL             7.06',
    left: 40,
    top: 350,
    width: 400,
    height: 34,
  ),
  OcrBlock(
    text: 'CASH             10.00',
    left: 40,
    top: 400,
    width: 400,
    height: 30,
  ),
  OcrBlock(
    text: 'CHANGE            2.94',
    left: 40,
    top: 440,
    width: 400,
    height: 30,
  ),
];
