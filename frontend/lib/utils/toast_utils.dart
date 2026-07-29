import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/services.dart';
import '../services/harmonyos_platform.dart';
import 'platform_detector.dart';

class ToastUtils {
  static const MethodChannel _channel = MethodChannel('com.example.mobile_portainer_flutter_module/channel');

  static void show(String message) {
    if (PlatformDetector.isOhos) {
      HarmonyosPlatform.showToast(message);
    } else if (PlatformDetector.isAndroid) {
      _channel.invokeMethod('showToast', message);
    } else {
      Fluttertoast.showToast(
        msg: message,
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        timeInSecForIosWeb: 1,
        backgroundColor: Colors.black87,
        textColor: Colors.white,
        fontSize: 16.0,
      );
    }
  }
}
