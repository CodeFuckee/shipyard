class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  Future<void> initialize() async {}

  Future<void> showAndroid(String title, String body) async {}
}
