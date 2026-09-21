import 'package:local_auth/local_auth.dart';

/// Whether the app should be showing its lock screen.
///
/// Pure, so the grace period can be tested without a clock or a fingerprint
/// reader. [unlockedAt] is null when the app has never been unlocked in this
/// process, which is the cold-start case.
bool shouldLock({
  required bool enabled,
  required DateTime? unlockedAt,
  required DateTime now,
  Duration grace = const Duration(minutes: 2),
}) {
  if (!enabled) return false;
  if (unlockedAt == null) return true;
  return now.difference(unlockedAt) >= grace;
}

/// Asks the device to confirm who is holding it.
abstract interface class AppLockService {
  /// Whether this device can authenticate at all.
  ///
  /// False on a device with no enrolled biometric *and* no PIN, and on
  /// anything below Android 6. The Settings toggle stays hidden in that case
  /// rather than offering a lock that cannot engage.
  Future<bool> isAvailable();

  /// Prompts, and reports whether the user got through.
  Future<bool> authenticate();
}

/// The real one, over `local_auth`.
class LocalAuthAppLockService implements AppLockService {
  LocalAuthAppLockService({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } on Exception {
      // A platform that throws rather than answering is a platform without
      // this. Reporting unavailable hides the toggle, which is the right
      // outcome either way.
      return false;
    }
  }

  @override
  Future<bool> authenticate() async {
    try {
      // local_auth 3.0.0 removed AuthenticationOptions and moved its fields
      // onto authenticate() directly.
      return await _auth.authenticate(
        localizedReason: 'Unlock LeafLine to see your expenses',
        // False on purpose, and the most important line here. A
        // biometric-only lock locks people out of their own data the first
        // time a wet thumb or a cracked sensor stops cooperating, and with no
        // account and no backend there is no recovery path at all. The device
        // PIN is always an acceptable answer.
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } on Exception {
      return false;
    }
  }
}

/// Reports unavailable and never prompts.
class UnavailableAppLockService implements AppLockService {
  const UnavailableAppLockService();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> authenticate() async => false;
}
