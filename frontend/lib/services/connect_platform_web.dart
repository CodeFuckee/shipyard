import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

/// 网页授权 /connect 流程的 Web 端平台能力:
/// 整页跳转、URL 清理、WebCrypto SHA-256、sessionStorage 存取。
/// 仅 Web 端可用;io 端对应 [connect_platform_io.dart] 为 stub。
class ConnectPlatform {
  ConnectPlatform._();

  /// 跳转到授权页(整页导航,离开本 app)。
  static Future<bool> redirect(String url) async {
    _getWindow.location.assign(url.toJS);
    return true;
  }

  /// 清理 URL 上的回调参数,防止刷新重复处理。
  static void replaceHistory(String url) {
    _getWindow.history.replaceState(null, ''.toJS, url.toJS);
  }

  /// 浏览器原生 WebCrypto 计算 SHA-256(hex),避免引入 crypto 依赖。
  static Future<String> sha256Hex(String input) async {
    final buffer = await _getCrypto.subtle
        .digest(
          'SHA-256'.toJS,
          Uint8List.fromList(utf8.encode(input)).toJS,
        )
        .toDart;
    final bytes = Uint8List.view(buffer.toDart);
    final hex = StringBuffer();
    for (final b in bytes) {
      hex.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return hex.toString();
  }

  /// 读取 sessionStorage,不存在时返回 null。
  static Future<String?> storageGet(String key) async {
    final raw = _getWindow.sessionStorage.getItem(key.toJS);
    return raw?.toDart;
  }

  static Future<void> storageSet(String key, String value) async {
    _getWindow.sessionStorage.setItem(key.toJS, value.toJS);
  }

  static Future<void> storageRemove(String key) async {
    _getWindow.sessionStorage.removeItem(key.toJS);
  }

  // ==================== 深链 ====================

  /// Web 端深链走整页导航 + URL 参数(Uri.base),不消费初始链接。
  static Future<Uri?> initialLink() async => null;

  /// Web 端深链走整页导航 + URL 参数(Uri.base),无热启动回跳流。
  static Future<Uri?> pendingLink() async => null;
}

// ================================================================
// JS interop(与 copy_helper_web.dart 同风格)
// ================================================================

/// JS window
extension type _Window(JSObject _) implements JSObject {
  external _Location get location;
  external _Storage get sessionStorage;
  external _History get history;
}

/// JS window.location
extension type _Location(JSObject _) implements JSObject {
  external void assign(JSString url);
}

/// JS window.sessionStorage
extension type _Storage(JSObject _) implements JSObject {
  external JSString? getItem(JSString key);
  external void setItem(JSString key, JSString value);
  external void removeItem(JSString key);
}

/// JS window.history
extension type _History(JSObject _) implements JSObject {
  external void replaceState(JSAny? state, JSString title, JSString url);
}

/// JS crypto(WebCrypto)
extension type _Crypto(JSObject _) implements JSObject {
  external _Subtle get subtle;
}

/// JS crypto.subtle
extension type _Subtle(JSObject _) implements JSObject {
  external JSPromise<JSArrayBuffer> digest(JSString algorithm, JSAny data);
}

@JS('window')
external _Window get _getWindow;

@JS('crypto')
external _Crypto get _getCrypto;
