import 'package:flutter/foundation.dart';

class PlatformDetector {
  static bool get isOhos => false;
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isWeb => kIsWeb;
}
