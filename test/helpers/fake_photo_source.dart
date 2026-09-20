import 'dart:convert';

import 'package:receipt_tracker/services/photo_source.dart';

/// A 1x1 transparent PNG.
///
/// Real image bytes, not filler. `Image.file` reports a decode failure to
/// `FlutterError.onError`, which a widget test treats as a failure — so a
/// fake handing back arbitrary bytes would fail tests for a reason that has
/// nothing to do with what they are checking.
final List<int> tinyImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
  'hQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// A [PhotoSource] that answers from memory.
///
/// `image_picker` is a platform channel; this is what makes the photo flow
/// testable at all.
class FakePhotoSource implements PhotoSource {
  FakePhotoSource({
    this.available = true,
    this.cancels = false,
    this.failure,
    List<int>? bytes,
  }) : bytes = bytes ?? tinyImageBytes;

  /// What [isAvailable] reports.
  final bool available;

  /// When true, both methods return null, as they do when the user backs out.
  final bool cancels;

  /// When set, both methods throw it.
  final PhotoFailure? failure;

  final List<int> bytes;

  int captureCount = 0;
  int pickCount = 0;

  @override
  bool get isAvailable => available;

  @override
  Future<CapturedPhoto?> capture() async {
    captureCount++;
    return _result();
  }

  @override
  Future<CapturedPhoto?> pick() async {
    pickCount++;
    return _result();
  }

  CapturedPhoto? _result() {
    final f = failure;
    if (f != null) throw f;
    if (cancels) return null;
    return CapturedPhoto(path: '/tmp/fake.jpg', bytes: bytes);
  }
}
