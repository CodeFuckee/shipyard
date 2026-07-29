import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/harmonyos_platform.dart';
import '../utils/platform_detector.dart';

class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    if (PlatformDetector.isOhos) {
      await HarmonyosPlatform.initializeNotifications();
      _initialized = true;
      return;
    }

    if (!PlatformDetector.isAndroid) {
      _initialized = true;
      return;
    }
    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(settings: initSettings);

    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  Future<void> showAndroid(String title, String body) async {
    if (PlatformDetector.isOhos) {
      await HarmonyosPlatform.showNotification(title, body);
      return;
    }

    if (!PlatformDetector.isAndroid) return;
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'general_channel',
      'General',
      channelDescription: 'General notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    final NotificationDetails details = NotificationDetails(android: androidDetails);
    await _plugin.show(id: 0, title: title, body: body, notificationDetails: details);
  }
}
