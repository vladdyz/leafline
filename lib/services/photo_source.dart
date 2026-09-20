import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Gets a photo from the camera or the gallery.
///
/// An interface for the same reason `OcrService` is one: `image_picker` is a
/// platform channel, so anything that calls it directly cannot be exercised
/// in a widget test. A fake implementation is an ordinary class.
abstract interface class PhotoSource {
  /// Whether a camera or gallery is reachable at all.
  bool get isAvailable;

  /// Opens the camera. Returns null when the user backs out.
  Future<CapturedPhoto?> capture();

  /// Opens the gallery. Returns null when the user backs out.
  Future<CapturedPhoto?> pick();
}

/// A photo the user chose, still sitting in a temporary location.
///
/// Not yet the app's: [ImageStore] copies the bytes into the documents
/// directory under the expense's id. The temp file is the picker's to clean
/// up.
class CapturedPhoto {
  const CapturedPhoto({required this.path, required this.bytes});

  final String path;
  final List<int> bytes;

  int get sizeBytes => bytes.length;
}

/// Why a photo could not be taken.
enum PhotoFailureKind {
  /// The user said no, and can be asked again.
  permissionDenied,

  /// The user said never. Only app settings can change it now.
  permissionPermanentlyDenied,

  /// No camera, or the platform has no picker.
  unavailable,

  unknown,
}

class PhotoFailure implements Exception {
  const PhotoFailure(this.kind, [this.message]);

  /// Maps `image_picker`'s platform error codes.
  ///
  /// The plugin reports refusal through `PlatformException` codes rather than
  /// a typed error, so this mapping is the boundary between its vocabulary
  /// and the app's.
  factory PhotoFailure.fromCode(String? code, [String? message]) {
    switch (code) {
      case 'camera_access_denied':
      case 'photo_access_denied':
        return PhotoFailure(PhotoFailureKind.permissionDenied, message);
      case 'camera_access_restricted':
      case 'photo_access_restricted':
        return PhotoFailure(
          PhotoFailureKind.permissionPermanentlyDenied,
          message,
        );
      case 'no_available_camera':
        return PhotoFailure(PhotoFailureKind.unavailable, message);
      default:
        return PhotoFailure(PhotoFailureKind.unknown, message);
    }
  }

  final PhotoFailureKind kind;
  final String? message;

  /// What to show the user. Short, and never mentions a platform error code.
  String get userMessage {
    switch (kind) {
      case PhotoFailureKind.permissionDenied:
        return 'Camera access is off. You can still type the amount in.';
      case PhotoFailureKind.permissionPermanentlyDenied:
        return 'Camera access is blocked in Settings. You can still type the '
            'amount in.';
      case PhotoFailureKind.unavailable:
        return 'No camera available on this device.';
      case PhotoFailureKind.unknown:
        return 'Could not open the camera. You can still type the amount in.';
    }
  }

  @override
  String toString() => 'PhotoFailure(${kind.name})';
}

/// The real thing, over `image_picker`.
class ImagePickerPhotoSource implements PhotoSource {
  ImagePickerPhotoSource({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Long edge, in pixels, that a captured photo is scaled down to.
  ///
  /// Text recognition needs the resolution; a human reading it back later
  /// does not need much more. `image_picker` does the scaling natively, which
  /// is why no image library is a dependency here.
  static const double maxEdge = 1600;

  /// JPEG quality. 80 is the point where receipts stay crisp and the file
  /// stops shrinking much.
  static const int quality = 80;

  @override
  bool get isAvailable => Platform.isAndroid || Platform.isIOS;

  @override
  Future<CapturedPhoto?> capture() => _get(ImageSource.camera);

  @override
  Future<CapturedPhoto?> pick() => _get(ImageSource.gallery);

  Future<CapturedPhoto?> _get(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: maxEdge,
        maxHeight: maxEdge,
        imageQuality: quality,
      );
      if (file == null) return null;
      return CapturedPhoto(path: file.path, bytes: await file.readAsBytes());
    } on PlatformException catch (error) {
      // image_picker reports refusal through a code rather than a typed
      // error, so this is the boundary between its vocabulary and the app's.
      throw PhotoFailure.fromCode(error.code, error.message);
    }
  }
}

/// Reports no camera and returns nothing.
///
/// Used on platforms with no picker. The form hides its photo controls rather
/// than offering something that cannot work.
class UnavailablePhotoSource implements PhotoSource {
  const UnavailablePhotoSource();

  @override
  bool get isAvailable => false;

  @override
  Future<CapturedPhoto?> capture() async => null;

  @override
  Future<CapturedPhoto?> pick() async => null;
}
