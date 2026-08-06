/// 网页授权 /connect 流程的 io 端(移动端/桌面端)平台能力。
///
/// 该流程仅 Web 端生效(kIsWeb 入口保护),io 端这些方法不会被调用,
/// 统一抛错保证"不静默降级"。详见 [connect_platform_web.dart]。
class ConnectPlatform {
  ConnectPlatform._();

  static void redirect(String url) {
    throw UnsupportedError('网页授权 /connect 流程仅 Web 端可用');
  }

  static void replaceHistory(String url) {
    throw UnsupportedError('网页授权 /connect 流程仅 Web 端可用');
  }

  static Future<String> sha256Hex(String input) async {
    throw UnsupportedError('网页授权 /connect 流程仅 Web 端可用');
  }

  static String? storageGet(String key) {
    throw UnsupportedError('网页授权 /connect 流程仅 Web 端可用');
  }

  static void storageSet(String key, String value) {
    throw UnsupportedError('网页授权 /connect 流程仅 Web 端可用');
  }

  static void storageRemove(String key) {
    throw UnsupportedError('网页授权 /connect 流程仅 Web 端可用');
  }
}
