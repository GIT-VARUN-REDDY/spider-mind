import 'package:flutter/foundation.dart';

/// Push notification service stub with Firebase Cloud Messaging (FCM) support.
///
/// Compile with `--dart-define=ENABLE_FCM=true` to enable push token sync.
/// In default builds, this operates as a self-contained, offline-safe stub
/// that coordinates with [NotificationService].
class PushService {
  static const bool enabled = bool.fromEnvironment('ENABLE_FCM', defaultValue: false);

  bool _initialized = false;
  String? _token;

  bool get isEnabled => enabled;
  bool get isInitialized => _initialized;
  String? get fcmToken => _token;

  Future<void> init({Future<void> Function(String token)? onTokenRefresh}) async {
    if (!enabled) {
      debugPrint('[PushService] FCM is disabled (use --dart-define=ENABLE_FCM=true to enable)');
      return;
    }
    _initialized = true;
    _token = 'stub_fcm_token_${DateTime.now().millisecondsSinceEpoch}';
    debugPrint('[PushService] Initialized with token: $_token');
    if (onTokenRefresh != null && _token != null) {
      await onTokenRefresh(_token!);
    }
  }

  Future<void> handleMessage(Map<String, dynamic> data) async {
    debugPrint('[PushService] Received push payload: $data');
  }
}
