import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api/api_client.dart';

/// Module 9 alert delivery on the device (FR-9.1, FR-9.5, D-33).
///
/// The FCM token is registered with FastAPI after sign-in and removed before sign-out,
/// so a shared phone stops receiving the previous user's alerts.
abstract interface class PushService {
  /// Ask for permission (Android 13+), then register this device for the signed-in user.
  Future<void> register();

  /// Remove this device's token while the user is still signed in.
  Future<void> unregister();
}

/// Web (staff portal) and tests: the doctor portal reads clinical_alerts live instead.
class NoopPushService implements PushService {
  const NoopPushService();

  @override
  Future<void> register() async {}

  @override
  Future<void> unregister() async {}
}

/// Channel ids match the backend's FcmPushClient.
const alertsChannel = AndroidNotificationChannel(
  'careflow_alerts',
  'Health alerts',
  description: 'Very high readings and critical risk changes',
  importance: Importance.max,
);
const generalChannel = AndroidNotificationChannel(
  'careflow_general',
  'Health updates',
  description: 'Readings, risk updates and reminders',
  importance: Importance.defaultImportance,
);

class FcmPushService implements PushService {
  FcmPushService(this._api, {FirebaseMessaging? messaging})
    : _messaging = messaging ?? FirebaseMessaging.instance;

  final ApiClient _api;
  final FirebaseMessaging _messaging;
  final _local = FlutterLocalNotificationsPlugin();
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _foreground;
  bool _started = false;
  String? _token;

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final android = _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(alertsChannel);
    await android?.createNotificationChannel(generalChannel);
    // FCM shows notifications itself only in the background; show foreground ones here.
    _foreground = FirebaseMessaging.onMessage.listen(_showForeground);
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;
    final channel = n.android?.channelId == alertsChannel.id ? alertsChannel : generalChannel;
    await _local.show(
      id: message.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: channel == alertsChannel ? Priority.high : Priority.defaultPriority,
        ),
      ),
    );
  }

  @override
  Future<void> register() async {
    try {
      await _start();
      await _messaging.requestPermission();
      final token = await _messaging.getToken();
      if (token == null) return;
      _token = token;
      await _api.registerFcmToken(token: token, platform: 'android');
      _refresh ??= _messaging.onTokenRefresh.listen((t) async {
        _token = t;
        await _api.registerFcmToken(token: t, platform: 'android');
      });
    } catch (e) {
      // Alerts are a convenience on top of the in-app banners; never block sign-in.
      debugPrint('Push registration failed: $e');
    }
  }

  @override
  Future<void> unregister() async {
    final token = _token ?? await _messaging.getToken().catchError((_) => null);
    await _refresh?.cancel();
    _refresh = null;
    if (token == null) return;
    try {
      await _api.removeFcmToken(token: token, platform: 'android');
    } catch (_) {
      // Best effort; FastAPI also drops tokens FCM rejects.
    }
    _token = null;
  }

  Future<void> dispose() async {
    await _refresh?.cancel();
    await _foreground?.cancel();
  }
}
