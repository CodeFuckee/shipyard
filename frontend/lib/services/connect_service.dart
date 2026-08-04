import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 跨实例服务器授权添加(Web 端 /connect 流程)。
///
/// 与后端 `app/routers/connect.py` 配合,类似 OAuth2 授权码 + PKCE:
///
///   探测 capabilities → 注册 public client → 跳转目标服务器授权页
///   → 用户登录/确认 → 302 回跳携带一次性 code
///   → 本服务用 sessionStorage 中的 verifier 换取独立 apikey
///
/// state 与 code_verifier 存 sessionStorage:整页跳转回跳后同一标签页可恢复,
/// 其他页面/标签页读取不到(防 CSRF;PKCE 保证 code 泄露也无法换 key)。
///
/// 仅 Web 端生效;移动端无此流程(深链基建待实现,见 GitLab issue)。
class ConnectFlow {
  final String serverUrl;
  final String clientId;
  final String state;
  final String verifier;
  final String redirectUri;

  const ConnectFlow({
    required this.serverUrl,
    required this.clientId,
    required this.state,
    required this.verifier,
    required this.redirectUri,
  });

  Map<String, String> toJson() => {
        'serverUrl': serverUrl,
        'clientId': clientId,
        'state': state,
        'verifier': verifier,
        'redirectUri': redirectUri,
      };

  static ConnectFlow? fromJson(Map<String, dynamic> json) {
    final serverUrl = json['serverUrl']?.toString();
    final clientId = json['clientId']?.toString();
    final state = json['state']?.toString();
    final verifier = json['verifier']?.toString();
    final redirectUri = json['redirectUri']?.toString();
    if (serverUrl == null ||
        clientId == null ||
        state == null ||
        verifier == null ||
        redirectUri == null) {
      return null;
    }
    return ConnectFlow(
      serverUrl: serverUrl,
      clientId: clientId,
      state: state,
      verifier: verifier,
      redirectUri: redirectUri,
    );
  }
}

class ConnectResult {
  final String serverUrl;
  final String apikey;
  const ConnectResult({required this.serverUrl, required this.apikey});
}

class ConnectService {
  ConnectService._();

  static const _storageKey = 'connect_flow';
  static const _clientName = 'Docker Monitor Web';

  /// 探测目标服务器是否支持 /connect 流程。
  ///
  /// 老版本部署的 nginx 会把 /connect/* 回退成 index.html(200 HTML),
  /// 因此必须解析 JSON 而非只看状态码;任何异常(超时/非 JSON/404)
  /// 一律视为不支持,由调用方回退手动输入。
  static Future<bool> probe(String serverUrl) async {
    if (!kIsWeb) return false;
    try {
      final resp = await http
          .get(Uri.parse('${serverUrl.trimRight()}/connect/capabilities'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(resp.body);
      return data is Map && data['enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 回调地址:本 app 当前部署的 origin + 固定路径。
  ///
  /// 目标服务器授权页与回跳都必须指向这个地址;SPA 回退机制
  /// 保证任意路径都能加载本 app,由 main.dart 在启动时解析参数。
  static String buildRedirectUri() => '${Uri.base.origin}/connect/callback';

  /// 在目标服务器上注册 public client 并构造授权页 URL。
  ///
  /// 完成后需要跳转到返回的 URL(window.location),整页离开本 app。
  /// state 与 verifier 已存入 sessionStorage,回跳后可恢复。
  static Future<String> buildAuthorizeUrl(String serverUrl) async {
    final redirectUri = buildRedirectUri();
    final resp = await http
        .post(
          Uri.parse('${serverUrl.trimRight()}/connect/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'redirect_uri': redirectUri,
            'client_name': _clientName,
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('服务器不支持授权添加(${resp.statusCode})');
    }
    final clientId =
        ((jsonDecode(resp.body) as Map)['client_id'] ?? '').toString();
    if (clientId.isEmpty) {
      throw Exception('注册失败:未返回 client_id');
    }

    final state = _randomToken(16);
    final verifier = _randomToken(48);
    final challenge = await _sha256Hex(verifier);

    _saveFlow(ConnectFlow(
      serverUrl: serverUrl.trimRight(),
      clientId: clientId,
      state: state,
      verifier: verifier,
      redirectUri: redirectUri,
    ));

    final params = Uri(queryParameters: {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'state': state,
      'code_challenge': challenge,
    }).query;
    return '$serverUrl/connect/authorize?$params';
  }

  /// 当前 URL 是否为 /connect 回跳(带 code 与 state 参数)。
  static bool isCallbackUri(Uri uri) {
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    return code != null && code.isNotEmpty && state != null && state.isNotEmpty;
  }

  /// 处理回跳:校验 state 后换取独立 apikey,并清理流程状态。
  ///
  /// 返回 null 表示参数缺失或 state 不匹配(非本流程发起的回跳),
  /// 调用方应忽略并正常启动。
  static Future<ConnectResult?> completeFlow(Uri uri) async {
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    if (code == null || code.isEmpty || state == null || state.isEmpty) {
      return null;
    }
    final flow = _loadFlow();
    if (flow == null || flow.state != state) return null;

    final resp = await http
        .post(
          Uri.parse('${flow.serverUrl}/connect/token'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'client_id': flow.clientId,
            'code': code,
            'code_verifier': flow.verifier,
          }),
        )
        .timeout(const Duration(seconds: 10));
    _clearFlow();
    if (resp.statusCode != 200) {
      throw Exception('授权码交换失败(${resp.statusCode})');
    }
    final apikey =
        ((jsonDecode(resp.body) as Map)['apikey'] ?? '').toString();
    if (apikey.isEmpty) {
      throw Exception('未返回 API 密钥');
    }
    return ConnectResult(serverUrl: flow.serverUrl, apikey: apikey);
  }

  /// 跳转到授权页(整页导航,离开本 app)。
  static void redirectTo(String url) {
    _getWindow.location.assign(url.toJS);
  }

  /// 清理 URL 上的回调参数,防止刷新重复处理。
  static void clearCallbackParams(Uri uri) {
    final clean = uri.toString().split('?').first;
    _getWindow.history.replaceState(null, ''.toJS, clean.toJS);
  }

  static String _randomToken(int bytes) {
    final rand = Random.secure();
    final list = Uint8List(bytes);
    for (var i = 0; i < bytes; i++) {
      list[i] = rand.nextInt(256);
    }
    return base64UrlEncode(list);
  }

  /// 浏览器原生 WebCrypto 计算 SHA-256(hex),避免引入 crypto 依赖。
  static Future<String> _sha256Hex(String input) async {
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

  static void _saveFlow(ConnectFlow flow) {
    _getWindow.sessionStorage
        .setItem(_storageKey.toJS, jsonEncode(flow.toJson()).toJS);
  }

  static ConnectFlow? _loadFlow() {
    final raw = _getWindow.sessionStorage.getItem(_storageKey.toJS);
    if (raw == null || raw.toDart.isEmpty) return null;
    try {
      final data = jsonDecode(raw.toDart);
      return data is Map
          ? ConnectFlow.fromJson(Map<String, dynamic>.from(data))
          : null;
    } catch (_) {
      return null;
    }
  }

  static void _clearFlow() {
    _getWindow.sessionStorage.removeItem(_storageKey.toJS);
  }
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
