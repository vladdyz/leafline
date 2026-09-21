import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:receipt_tracker/services/notification_service.dart';

/// The real one, over `flutter_local_notifications`.
///
/// No backend, no gateway, no contact details stored anywhere. See decision
/// 0007 on why SMS and email were rejected: they would require the entire
/// sync backend in order to deliver a message to the phone already in the
/// user's hand.
class LocalNotificationService implements NotificationService {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// The channel budget warnings arrive on.
  ///
  /// One channel, so a user who finds these intrusive can silence exactly
  /// these from Android's own settings without losing anything else the app
  /// might send later.
  static const String channelId = 'budget_alerts';
  static const String channelName = 'Budget warnings';
  static const String channelDescription =
      'Tells you when a week is approaching or has passed its budget.';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  @override
  bool get isSupported => Platform.isAndroid || Platform.isIOS;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    await _plugin.initialize(
      settings: const InitializationSettings(
        // NOT '@mipmap/ic_launcher'. Android renders a status-bar icon from
        // its alpha channel alone and paints the result white, so a full
        // colour launcher icon arrives as a featureless white square. This
        // is a white silhouette on transparent, at the five densities
        // Android expects.
        android: AndroidInitializationSettings('@drawable/ic_notification'),
      ),
    );

    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDescription,
        importance: Importance.defaultImportance,
      ),
    );

    _initialized = true;
  }

  @override
  Future<bool> ensurePermission() async {
    await initialize();

    final android = _android;
    if (android == null) return true;

    if (await android.areNotificationsEnabled() ?? false) return true;
    // Android 13+ only. On older versions this resolves true without a
    // prompt, because the permission did not exist.
    return await android.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    await initialize();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }

  @override
  Future<void> cancel(int id) async {
    await initialize();
    await _plugin.cancel(id: id);
  }
}
