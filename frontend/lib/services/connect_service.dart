import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'connect_platform.dart';

/// 跨实例服务器授权添加(/connect 流程,Web 与移动端共享同一套协议)。
///
/// 与后端 `app/routers/connect.py` 配合,类似 OAuth2 授权码 + PKCE:
///
///   探测 capabilities → 注册 public client → 跳转目标服务器授权页
///   → 用户登录/确认 → 回跳携带一次性 code(Web 302 / 移动端深链)
///   → 本服务用已保存的 verifier 换取独立 apikey
///
/// state 与 code_verifier 的存储平台化(ConnectPlatform):
/// Web 存 sessionStorage(整页跳转回跳后同一标签页可恢复,防 CSRF;
/// PKCE 保证 code 泄露也无法换 key);移动端存 SharedPreferences/
/// 鸿蒙 preferences(冷启动恢复后仍可完成交换)。
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

  /// 测试注入的 http client(与 ServerListStorage.debugHttpClient 同模式)。
  static http.Client? debugHttpClient;

  static http.Client get _client => debugHttpClient ?? http.Client();

  /// 注册时上报的客户端名(Web/移动端区分,便于目标服务器侧识别来源)。
  static String get _clientName =>
      kIsWeb ? 'Docker Monitor Web' : 'Docker Monitor Mobile';

  /// 探测目标服务器是否支持 /connect 流程。
  ///
  /// 老版本部署的 nginx 会把 /connect/* 回退成 index.html(200 HTML),
  /// 因此必须解析 JSON 而非只看状态码;任何异常(超时/非 JSON/404)
  /// 一律视为不支持,由调用方回退手动输入。
  static Future<bool> probe(String serverUrl) async {
    try {
      final resp = await _client
          .get(Uri.parse('${serverUrl.trimRight()}/connect/capabilities'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(resp.body);
      return data is Map && data['enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 回调地址:Web 为当前部署 origin + 固定路径(整页跳转回跳);
  /// 移动端为 `shipyard://connect/callback` 自定义 scheme(深链回跳)。
  ///
  /// 目标服务器授权页与回跳都必须指向这个地址;Web 端 SPA 回退机制
  /// 保证任意路径都能加载本 app,由 main.dart 在启动时解析参数。
  static String buildRedirectUri() {
    if (kIsWeb) return '${Uri.base.origin}/connect/callback';
    return 'shipyard://connect/callback';
  }

  /// 在目标服务器上注册 public client 并构造授权页 URL。
  ///
  /// 完成后需要跳转到返回的 URL(window.location),整页离开本 app。
  /// state 与 verifier 已存入 sessionStorage,回跳后可恢复。
  static Future<String> buildAuthorizeUrl(String serverUrl) async {
    final redirectUri = buildRedirectUri();
    final resp = await _client
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

    await _saveFlow(ConnectFlow(
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
    final flow = await _loadFlow();
    if (flow == null || flow.state != state) return null;

    final resp = await _client
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
    await _clearFlow();
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

  /// 跳转到授权页。
  ///
  /// Web 端整页导航(离开本 app);移动端打开系统浏览器,
  /// 授权完成后经 `shipyard://` 深链回跳。
  static Future<bool> redirectTo(String url) {
    return ConnectPlatform.redirect(url);
  }

  /// 清理 URL 上的回调参数,防止刷新重复处理(仅 Web 端有 URL)。
  static void clearCallbackParams(Uri uri) {
    final clean = uri.toString().split('?').first;
    ConnectPlatform.replaceHistory(clean);
  }

  /// 冷启动深链(app 被系统拉起时携带的回跳地址)。
  static Future<Uri?> initialLink() {
    return ConnectPlatform.initialLink();
  }

  /// 热启动深链(app 从后台恢复时收到的回跳地址,消费后清空)。
  static Future<Uri?> pendingLink() {
    return ConnectPlatform.pendingLink();
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
  static Future<String> _sha256Hex(String input) {
    return ConnectPlatform.sha256Hex(input);
  }

  static Future<void> _saveFlow(ConnectFlow flow) async {
    await ConnectPlatform.storageSet(_storageKey, jsonEncode(flow.toJson()));
  }

  static Future<ConnectFlow?> _loadFlow() async {
    final raw = await ConnectPlatform.storageGet(_storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw);
      return data is Map
          ? ConnectFlow.fromJson(Map<String, dynamic>.from(data))
          : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _clearFlow() async {
    await ConnectPlatform.storageRemove(_storageKey);
  }
}
