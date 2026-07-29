import 'package:flutter/services.dart';

/// 统一鸿蒙平台通道，替代以下不兼容库的原生实现:
/// shared_preferences, path_provider, share_plus, permission_handler,
/// device_info_plus, package_info_plus, url_launcher, fluttertoast,
/// flutter_local_notifications, mobile_scanner
class HarmonyosPlatform {
  static const String _channelName = 'com.chenkaidi.mobileportainer/harmonyos';
  static const MethodChannel _channel = MethodChannel(_channelName);

  // ==================== SharedPreferences ====================

  static Future<String?> getString(String key) async {
    return await _channel.invokeMethod<String>('getString', {'key': key});
  }

  static Future<bool> setString(String key, String value) async {
    return await _channel.invokeMethod<bool>('setString', {
      'key': key,
      'value': value,
    }) ?? false;
  }

  static Future<bool> remove(String key) async {
    return await _channel.invokeMethod<bool>('removeString', {'key': key}) ?? false;
  }

  // ==================== PackageInfo ====================

  static Future<Map<String, dynamic>> getPackageInfo() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getPackageInfo');
    if (result == null) {
      return {'version': '1.0.0', 'buildNumber': '1'};
    }
    return Map<String, dynamic>.from(result);
  }

  // ==================== UrlLauncher ====================

  static Future<bool> launchUrl(String url) async {
    return await _channel.invokeMethod<bool>('launchUrl', {'url': url}) ?? false;
  }

  // ==================== PathProvider ====================

  static Future<String> getTemporaryDirectory() async {
    return await _channel.invokeMethod<String>('getTemporaryDirectory') ?? '';
  }

  static Future<String> getDownloadsDirectory() async {
    return await _channel.invokeMethod<String>('getDownloadsDirectory') ?? '';
  }

  // ==================== Share ====================

  static Future<bool> shareFile(String filePath, {String? text}) async {
    return await _channel.invokeMethod<bool>('shareFile', {
      'path': filePath,
      'text': text ?? '',
    }) ?? false;
  }

  // ==================== PermissionHandler ====================

  static Future<int> checkPermission(String permission) async {
    return await _channel.invokeMethod<int>('checkPermission', {
      'permission': permission,
    }) ?? -1;
  }

  static Future<int> requestPermission(String permission) async {
    return await _channel.invokeMethod<int>('requestPermission', {
      'permission': permission,
    }) ?? -1;
  }

  // ==================== DeviceInfo ====================

  static Future<Map<String, dynamic>> getDeviceInfo() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getDeviceInfo');
    if (result == null) {
      return {'sdkInt': 12};
    }
    return Map<String, dynamic>.from(result);
  }

  // ==================== Toast ====================

  static Future<void> showToast(String message) async {
    await _channel.invokeMethod('showToast', {'message': message});
  }

  // ==================== Notifications ====================

  static Future<bool> initializeNotifications() async {
    return await _channel.invokeMethod<bool>('initNotifications') ?? false;
  }

  static Future<void> showNotification(String title, String body) async {
    await _channel.invokeMethod('showNotification', {
      'title': title,
      'body': body,
    });
  }

  // ==================== QR Scanner ====================

  static Future<String?> scanQrCode() async {
    return await _channel.invokeMethod<String>('scanQrCode');
  }

  // ==================== Split Screen ====================

  /// 退出分屏模式。原生端检查当前是否处于分屏状态：
  /// - 若在分屏中，退出分屏并返回 true
  /// - 若不在分屏中，返回 false
  static Future<bool> exitSplitScreen() async {
    return await _channel.invokeMethod<bool>('exitSplitScreen') ?? false;
  }
}
