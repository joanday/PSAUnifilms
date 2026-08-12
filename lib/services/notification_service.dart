import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  'new_uploads_channel',
  'New Uploads',
  description: 'Notifies you when a new film is uploaded',
  importance: Importance.high,
);

class NotificationService {
  static Future<void> initialize() async {
    // Request permission (iOS + Android 13+)
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Subscribe every user to the "new_uploads" topic
    await FirebaseMessaging.instance.subscribeToTopic('new_uploads');

    // Set up local notifications (for foreground display)
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _localNotifications.initialize(initSettings);

    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);

    // Foreground messages (app open) — show a local notification manually
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification != null) {
        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
      }
    });

    // When user taps a notification and opens the app from background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      // Optional: navigate to the new film's detail screen here
    });
  }
}
