import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:url_launcher/url_launcher.dart';

import '../utils/platform_detector.dart';
import 'harmonyos_platform.dart';
import 'platform/preferences_service.dart';

/// 网页授权 /connect 流程的移动端/桌面端(io)平台能力:
/// 系统浏览器跳转、纯 Dart SHA-256、SharedPreferences 存取、深链消费。
///
/// - Android/iOS/桌面:url_launcher + app_links(需要宿主工程声明
///   `shipyard://` scheme,见 docs/connect-flow-mobile.md)
/// - 鸿蒙:url_launcher 与 app_links 均不可用,统一走
///   [HarmonyosPlatform] 的 MethodChannel(深链由原生 EntryAbility
///   捕获后经通道消费)
///
/// Web 端对应 [connect_platform_web.dart]。
class ConnectPlatform {
  ConnectPlatform._();

  /// 跳转到授权页:鸿蒙走系统 Want,其余走系统浏览器。
  ///
  /// 返回是否成功发起跳转;失败不抛异常(由调用方提示用户)。
  static Future<bool> redirect(String url) async {
    if (PlatformDetector.isOhos) {
      return HarmonyosPlatform.launchUrl(url);
    }
    try {
      var launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        launched = await launchUrl(Uri.parse(url));
      }
      return launched;
    } catch (_) {
      return false;
    }
  }

  /// 移动端 scheme 回跳不改变 app 内页面地址,无需清理 URL 参数。
  static void replaceHistory(String url) {
    // no-op
  }

  /// 纯 Dart 实现 SHA-256(hex),与 Web 端 WebCrypto 输出一致。
  static Future<String> sha256Hex(String input) async {
    final bytes = crypto.sha256.convert(utf8.encode(input)).bytes;
    final hex = StringBuffer();
    for (final b in bytes) {
      hex.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return hex.toString();
  }

  /// 读取流程状态存储,不存在时返回 null。
  ///
  /// 与 Web 端 sessionStorage 同 key(`connect_flow`),移动端持久化到
  /// SharedPreferences(Android/iOS)或鸿蒙 preferences,冷启动后仍可恢复。
  static Future<String?> storageGet(String key) async {
    final prefs = await PreferencesService.getInstance();
    return prefs.getString(key);
  }

  static Future<void> storageSet(String key, String value) async {
    final prefs = await PreferencesService.getInstance();
    await prefs.setString(key, value);
  }

  static Future<void> storageRemove(String key) async {
    final prefs = await PreferencesService.getInstance();
    await prefs.remove(key);
  }

  // ==================== 深链 ====================

  static AppLinks? _appLinks;
  static Uri? _lastStreamLink;
  static StreamSubscription<Uri>? _streamSubscription;

  static AppLinks get _links => _appLinks ??= AppLinks();

  /// 冷启动回跳(app 被系统拉起):返回本次启动携带的深链 URI,消费后清空。
  ///
  /// 鸿蒙从原生缓存消费(EntryAbility.onCreate 时存入);
  /// Android/iOS 走 app_links 的 getInitialLink(本身就是消费语义)。
  static Future<Uri?> initialLink() async {
    if (PlatformDetector.isOhos) {
      return HarmonyosPlatform.getInitialDeepLink();
    }
    try {
      return await _links.getInitialLink();
    } catch (_) {
      return null;
    }
  }

  /// 热启动回跳(app 从后台恢复):消费最近一次深链。
  ///
  /// 鸿蒙由原生 onNewWant 捕获后存入队列,此处消费队首;
  /// Android/iOS 惰性订阅 app_links 的 uriLinkStream,缓存最近一条。
  static Future<Uri?> pendingLink() async {
    if (PlatformDetector.isOhos) {
      return HarmonyosPlatform.consumeDeepLink();
    }
    try {
      _streamSubscription ??= _links.uriLinkStream.listen(
        (raw) {
          _lastStreamLink = raw;
        },
        // 平台通道不可用(如 VM 测试)时忽略流错误
        onError: (_) {},
      );
      final link = _lastStreamLink;
      _lastStreamLink = null;
      return link;
    } catch (_) {
      return null;
    }
  }
}
