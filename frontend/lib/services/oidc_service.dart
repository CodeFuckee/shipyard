import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'connect_platform.dart';

class OidcException implements Exception {
  final String message;
  const OidcException(this.message);

  @override
  String toString() => message;
}

class OidcResult {
  final String serverUrl;
  final String apiKey;
  const OidcResult({required this.serverUrl, required this.apiKey});
}

class _OidcFlow {
  final String serverUrl;
  final String state;
  final String nonce;
  final String verifier;
  final String redirectUri;

  const _OidcFlow({
    required this.serverUrl,
    required this.state,
    required this.nonce,
    required this.verifier,
    required this.redirectUri,
  });

  Map<String, String> toJson() => {
    'serverUrl': serverUrl,
    'state': state,
    'nonce': nonce,
    'verifier': verifier,
    'redirectUri': redirectUri,
  };

  static _OidcFlow? fromJson(Map<String, dynamic> json) {
    final values = [
      json['serverUrl'],
      json['state'],
      json['nonce'],
      json['verifier'],
      json['redirectUri'],
    ].map((value) => value?.toString()).toList();
    if (values.any((value) => value == null || value.isEmpty)) {
      return null;
    }
    return _OidcFlow(
      serverUrl: values[0]!,
      state: values[1]!,
      nonce: values[2]!,
      verifier: values[3]!,
      redirectUri: values[4]!,
    );
  }
}

/// OIDC 授权码 + PKCE 登录流程。
///
/// IdP 令牌不落地，客户端只把 code、PKCE verifier 与 nonce 交给 Shipyard
/// 后端；后端完成 token 交换和签名验证，再返回已有 API 调用兼容的 API Key。
class OidcService {
  OidcService._();

  static const _storageKey = 'oidc_flow';
  static const _serverUrlKey = 'oidc_server_url';
  static http.Client? debugHttpClient;

  static http.Client get _client => debugHttpClient ?? http.Client();

  static String buildRedirectUri() {
    if (kIsWeb) return '${Uri.base.origin}/oidc/callback';
    return 'shipyard://oidc/callback';
  }

  static bool isCallbackUri(Uri uri) {
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    return code != null && code.isNotEmpty && state != null && state.isNotEmpty;
  }

  /// 保存后端地址，供原生端在登录页发起 OIDC 授权使用。
  static Future<void> saveServerUrl(String serverUrl) async {
    final cleanUrl = _cleanUrl(serverUrl.trim());
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const OidcException('请输入有效的 http 或 https 服务器地址');
    }
    await ConnectPlatform.storageSet(_serverUrlKey, cleanUrl);
  }

  static Future<String?> savedServerUrl() =>
      ConnectPlatform.storageGet(_serverUrlKey);

  static Future<String> buildAuthorizeUrl(String serverUrl) async {
    final cleanUrl = _cleanUrl(serverUrl);
    final response = await _client
        .get(Uri.parse('$cleanUrl/admin/oidc/config'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw const OidcException('无法读取 OIDC 登录配置');
    }
    final config = _decodeObject(response.body);
    if (config['enabled'] != true) {
      throw const OidcException('当前服务器未启用 OIDC 登录');
    }
    final endpoint = config['authorization_endpoint']?.toString();
    final clientId = config['client_id']?.toString();
    final scopes = config['scopes'];
    if (endpoint == null ||
        endpoint.isEmpty ||
        clientId == null ||
        clientId.isEmpty) {
      throw const OidcException('OIDC 登录配置不完整');
    }

    final state = _randomToken(32);
    final nonce = _randomToken(32);
    final verifier = _randomToken(64);
    final redirectUri = buildRedirectUri();
    final challenge = await ConnectPlatform.sha256Hex(verifier);
    await _saveFlow(
      _OidcFlow(
        serverUrl: cleanUrl,
        state: state,
        nonce: nonce,
        verifier: verifier,
        redirectUri: redirectUri,
      ),
    );

    final scopeText = scopes is List
        ? scopes
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .join(' ')
        : 'openid profile email';
    return Uri.parse(endpoint)
        .replace(
          queryParameters: {
            ...Uri.parse(endpoint).queryParameters,
            'client_id': clientId,
            'redirect_uri': redirectUri,
            'response_type': 'code',
            'scope': scopeText,
            'state': state,
            'nonce': nonce,
            'code_challenge': challenge,
            'code_challenge_method': 'S256',
          },
        )
        .toString();
  }

  static Future<OidcResult?> completeFlow(Uri uri) async {
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    if (code == null || code.isEmpty || state == null || state.isEmpty) {
      return null;
    }
    final flow = await _loadFlow();
    if (flow == null || flow.state != state) {
      return null;
    }

    try {
      final response = await _client
          .post(
            Uri.parse('${flow.serverUrl}/admin/oidc/exchange'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': code,
              'code_verifier': flow.verifier,
              'nonce': flow.nonce,
              'redirect_uri': flow.redirectUri,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw const OidcException('OIDC 登录验证失败');
      }
      final apiKey = _decodeObject(response.body)['api_key']?.toString();
      if (apiKey == null || apiKey.isEmpty) {
        throw const OidcException('OIDC 登录未返回 API Key');
      }
      return OidcResult(serverUrl: flow.serverUrl, apiKey: apiKey);
    } finally {
      // 无论交换成功或失败都消费一次状态，避免旧授权码被重放。
      await _clearFlow();
    }
  }

  static Future<bool> redirectTo(String url) => ConnectPlatform.redirect(url);

  static void clearCallbackParams(Uri uri) {
    ConnectPlatform.replaceHistory(uri.toString().split('?').first);
  }

  static Future<Uri?> initialLink() => ConnectPlatform.initialLink();
  static Future<Uri?> pendingLink() => ConnectPlatform.pendingLink();

  static Map<String, dynamic> _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    throw const OidcException('OIDC 服务响应格式不正确');
  }

  static String _cleanUrl(String serverUrl) => serverUrl.endsWith('/')
      ? serverUrl.substring(0, serverUrl.length - 1)
      : serverUrl;

  static String _randomToken(int bytes) {
    final random = Random.secure();
    final values = List<int>.generate(bytes, (_) => random.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', '');
  }

  static Future<void> _saveFlow(_OidcFlow flow) =>
      ConnectPlatform.storageSet(_storageKey, jsonEncode(flow.toJson()));

  static Future<_OidcFlow?> _loadFlow() async {
    final raw = await ConnectPlatform.storageGet(_storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? _OidcFlow.fromJson(Map<String, dynamic>.from(decoded))
          : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _clearFlow() =>
      ConnectPlatform.storageRemove(_storageKey);
}
