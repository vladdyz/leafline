import 'package:receipt_tracker/services/notification_service.dart';

/// One notification the app tried to show.
class ShownNotification {
  const ShownNotification({
    required this.id,
    required this.title,
    required this.body,
  });

  final int id;
  final String title;
  final String body;

  @override
  String toString() => 'ShownNotification($id, "$title", "$body")';
}

/// A [NotificationService] that records rather than notifies.
class FakeNotificationService implements NotificationService {
  /// Whether the platform claims to support notifications.
  bool supported = true;

  /// What [ensurePermission] reports.
  bool permissionGranted = true;

  /// Every notification shown, in order.
  final List<ShownNotification> shown = <ShownNotification>[];

  /// Ids passed to [cancel].
  final List<int> cancelled = <int>[];

  int initializeCount = 0;
  int permissionRequests = 0;

  @override
  bool get isSupported => supported;

  @override
  Future<void> initialize() async => initializeCount++;

  @override
  Future<bool> ensurePermission() async {
    permissionRequests++;
    return permissionGranted;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    shown.add(ShownNotification(id: id, title: title, body: body));
  }

  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}
