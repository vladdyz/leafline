/// Renders a byte count for people rather than for machines.
///
/// Binary units with decimal-ish labels, matching what Android's own storage
/// screens show — a user comparing this figure against Settings should see the
/// same number, not one 5% different because of a units argument.
String formatBytes(int bytes) {
  if (bytes < 0) return '0 KB';
  if (bytes < 1024) return '$bytes B';

  const int kb = 1024;
  const int mb = kb * 1024;
  const int gb = mb * 1024;

  if (bytes < mb) return '${(bytes / kb).round()} KB';
  if (bytes < gb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / gb).toStringAsFixed(2)} GB';
}

/// `12 photos`, `1 photo`, `No photos`.
String formatPhotoCount(int count) {
  if (count == 0) return 'No photos';
  if (count == 1) return '1 photo';
  return '$count photos';
}
