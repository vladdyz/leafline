/// Shows a system notification.
///
/// An interface for the same reason every other platform boundary here is
/// one: `flutter_local_notifications` is a plugin, and a widget test cannot
/// drive it. A fake is an ordinary class.
abstract interface class NotificationService {
  /// Whether this platform can show notifications at all.
  bool get isSupported;

  /// Prepares the plugin. Safe to call more than once.
  Future<void> initialize();

  /// Asks for permission if it has not been granted, and reports the result.
  ///
  /// Called at the moment a notification would fire rather than at launch.
  /// Someone who has just crossed their budget has context for the request;
  /// someone opening the app for the first time does not.
  Future<bool> ensurePermission();

  /// Shows a notification, replacing any previous one with the same [id].
  ///
  /// Reusing an id is deliberate: two warnings about the same week should
  /// replace one another rather than stack.
  Future<void> show({
    required int id,
    required String title,
    required String body,
  });

  /// Removes any notification previously shown with [id].
  Future<void> cancel(int id);
}

/// Reports unsupported and does nothing.
///
/// Used on platforms with no implementation, and in tests that care about
/// something else.
class UnavailableNotificationService implements NotificationService {
  const UnavailableNotificationService();

  @override
  bool get isSupported => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> ensurePermission() async => false;

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancel(int id) async {}
}
