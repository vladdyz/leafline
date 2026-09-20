import 'dart:io';

import 'package:flutter/services.dart';
import 'package:receipt_tracker/models/ocr_block.dart';
import 'package:receipt_tracker/services/ocr_service.dart';

/// Text recognition over the platform channel to the Kotlin plugin.
///
/// Kotlin returns recognised text and nothing more; deciding which number is
/// the total happens in Dart, in `TotalExtractor`. See decision 0003.
class ChannelOcrService implements OcrService {
  const ChannelOcrService();

  /// Must match `OcrPlugin.CHANNEL` exactly.
  ///
  /// A mismatch does not fail loudly — it surfaces as `MissingPluginException`,
  /// which reads as "the plugin was never registered" rather than "these two
  /// strings differ by a character". Hence the channel name being a plain
  /// literal on both sides rather than something derived from a package name.
  static const String channelName = 'receipt_tracker/ocr';

  static const MethodChannel _channel = MethodChannel(channelName);

  /// Android only. iOS needs a Swift implementation of the same contract
  /// against Apple's Vision framework — see the Platform support section of
  /// the design doc.
  @override
  bool get isAvailable => Platform.isAndroid;

  @override
  Future<List<OcrBlock>> recognize(String path) async {
    try {
      final result = await _channel.invokeListMethod<Object?>(
        'recognizeText',
        <String, Object?>{'path': path},
      );
      if (result == null) return const <OcrBlock>[];

      // Anything that is not a map is skipped rather than throwing. One
      // malformed entry should cost one line of a receipt, not the receipt.
      return result
          .whereType<Map<Object?, Object?>>()
          .map(OcrBlock.fromChannel)
          .toList();
    } on PlatformException catch (error) {
      throw OcrFailure.fromCode(error.code, error.message);
    } on MissingPluginException catch (error) {
      // Nothing is listening on the other side. Almost always a registration
      // that was never added to MainActivity, or a channel name typo — so it
      // is reported rather than quietly returning no candidates, which would
      // look identical to a photo of a blank wall.
      throw OcrFailure(
        OcrFailureKind.unknown,
        'No OCR plugin is registered on "$channelName". Check that '
        'MainActivity calls OcrPlugin.register(). (${error.message})',
      );
    }
  }
}
