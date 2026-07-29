import 'dart:io';

class PlatformDetector {
  static bool get isOhos => Platform.operatingSystem == 'ohos';
  static bool get isAndroid => Platform.isAndroid;
  static bool get isIOS => Platform.isIOS;
  static bool get isWeb => false;
}
