import 'package:flutter/services.dart';
import '../utils/platform_detector.dart';
import 'harmonyos_platform.dart';

/// 系统返回键处理服务
///
/// 鸿蒙端系统返回手势由原生宿主 App 处理，需要原生端通过 MethodChannel
/// 调用 [handleBackPressed] 询问 Flutter 是否拦截。
///
/// 原生端需调用 MethodChannel 'com.chenkaidi.mobileportainer/harmonyos'
/// 的 'onBackPressed' 方法，Flutter 返回 true（已拦截）或 false（原生端自行处理）。
///
/// 支持多个 handler 按 LIFO 顺序调用，任意一个返回 true 即拦截。
///
/// 分屏模式下优先退出分屏而不关闭应用。
class BackPressService {
  static const String _channelName = 'com.chenkaidi.mobileportainer/harmonyos';
  static final MethodChannel _channel = MethodChannel(_channelName);

  static final List<bool Function()> _handlers = [];

  /// 注册返回键拦截器，返回 true 表示已拦截。
  static void addHandler(bool Function() handler) {
    _handlers.add(handler);
  }

  /// 移除返回键拦截器。
  static void removeHandler(bool Function() handler) {
    _handlers.remove(handler);
  }

  /// 初始化：设置 MethodChannel handler，供原生端调用
  static void initialize() {
    if (!PlatformDetector.isOhos) return;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onBackPressed') {
        // 分屏状态下优先退出分屏，而非关闭应用
        final exited = await HarmonyosPlatform.exitSplitScreen();
        if (exited) return true;

        // LIFO: 后注册的优先处理（子 widget 先于父 widget）
        for (int i = _handlers.length - 1; i >= 0; i--) {
          if (_handlers[i]()) {
            return true;
          }
        }
        return false;
      }
      throw MissingPluginException('Not implemented: ${call.method}');
    });
  }
}
