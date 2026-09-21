import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receipt_tracker/state/providers.dart';

/// A small square preview of a stored receipt.
///
/// Resolves the filename through [imageStoreProvider] rather than taking a
/// path, because only the image store knows where the documents directory is
/// today — see decision 0002 on why the database holds filenames.
///
/// A missing file renders a placeholder rather than an error. That is an
/// expected state, not a fault: a photo can age out under the retention
/// policy while its expense lives on forever.
class ReceiptThumbnail extends ConsumerWidget {
  const ReceiptThumbnail({
    required this.photoFile,
    this.size = 40,
    this.onTap,
    super.key,
  });

  final String photoFile;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(imageStoreProvider);
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: size,
          height: size,
          child: Image.file(
            // Without this a screen reader announces nothing at all for the
            // photo — not "image", not "unlabelled". It is skipped silently,
            // so a blind user has no way to know a receipt is attached.
            semanticLabel: 'Receipt photo',
            store.fileFor(photoFile),
            fit: BoxFit.cover,
            // Without this, a rebuild re-decodes the JPEG from disk on every
            // frame of a scroll.
            cacheWidth: (size * 3).round(),
            errorBuilder: (context, error, stack) => Container(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.image_not_supported_outlined,
                size: size * 0.5,
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The receipt, full screen, pinch to zoom.
class PhotoViewScreen extends ConsumerWidget {
  const PhotoViewScreen({required this.photoFile, super.key});

  final String photoFile;

  static Future<void> open(BuildContext context, String photoFile) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoViewScreen(photoFile: photoFile),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(imageStoreProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Receipt'),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Image.file(
            // Without this a screen reader announces nothing at all for the
            // photo — not "image", not "unlabelled". It is skipped silently,
            // so a blind user has no way to know a receipt is attached.
            semanticLabel: 'Receipt photo',
            store.fileFor(photoFile),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'This photo is no longer stored.',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The photo control on the expense form: add, replace, view or remove.
class ReceiptPhotoField extends StatelessWidget {
  const ReceiptPhotoField({
    required this.photoFile,
    required this.busy,
    required this.onCapture,
    required this.onPickFromGallery,
    required this.onRemove,
    super.key,
  });

  final String? photoFile;
  final bool busy;
  final VoidCallback onCapture;
  final VoidCallback onPickFromGallery;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = photoFile;

    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Receipt (optional)',
        border: OutlineInputBorder(),
      ),
      child: Row(
        children: <Widget>[
          if (file != null)
            ReceiptThumbnail(
              photoFile: file,
              size: 48,
              onTap: () => PhotoViewScreen.open(context, file),
            )
          else
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                color: theme.colorScheme.outline,
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              file == null
                  ? 'Snap the receipt, or skip it.'
                  : 'Tap the photo to view it full size.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...<Widget>[
            IconButton(
              icon: const Icon(Icons.photo_camera_outlined),
              tooltip: file == null ? 'Take a photo' : 'Replace photo',
              onPressed: onCapture,
            ),
            IconButton(
              icon: const Icon(Icons.photo_library_outlined),
              tooltip: 'Choose from gallery',
              onPressed: onPickFromGallery,
            ),
            if (file != null)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Remove photo',
                onPressed: onRemove,
              ),
          ],
        ],
      ),
    );
  }
}
