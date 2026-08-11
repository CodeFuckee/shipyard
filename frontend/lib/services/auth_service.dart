import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import '../utils/platform_detector.dart';
import 'platform/http_helper.dart';
import 'platform/preferences_service.dart';

class AuthResult {
  final bool success;
  final String? token;
  final String? error;

  AuthResult._({required this.success, this.token, this.error});

  factory AuthResult.ok(String token) => AuthResult._(success: true, token: token);
  factory AuthResult.fail(String error) => AuthResult._(success: false, error: error);
}

class AuthService {
  static const _tokenKey = 'docker_auth_token';
  static const _serverUrlKey = 'docker_auth_server_url';
  // 登录服务器凭据：服务器列表（ServerListStorage）的固定读写目标。
  // docker_auth_* 会随切换活动服务器被同步覆盖（服务 API Key 管理等
  // Web 功能跟随），若列表也用它作目标会漂移到被添加的服务器——
  // 因此登录时额外保存一份永不随切换改变的副本。
  static const _webBackendUrlKey = 'web_backend_url';
  static const _webBackendTokenKey = 'web_backend_token';

  /// 测试注入的 http client（token 有效性验证使用）。
  /// VM 测试环境中 Web 分支默认走真实网络，通过该字段注入 MockClient。
  static http.Client? debugHttpClient;

  /// 测试开关：强制走 Web 分支（VM 中 PlatformDetector.isWeb 恒为 false）。
  static bool? debugForceWeb;

  static bool get _isWeb => debugForceWeb ?? PlatformDetector.isWeb;

  /// Web 端：通过 /admin/keys 获取 API Key
  /// 原生端：通过 Portainer /api/auth 获取 JWT
  static Future<AuthResult> login({
    required String serverUrl,
    required String username,
    required String password,
    bool ignoreSsl = false,
  }) async {
    if (PlatformDetector.isWeb) {
      return _loginWeb(serverUrl, username, password);
    }
    return _loginNative(serverUrl, username, password, ignoreSsl);
  }

  /// Web 端登录：GET /admin/keys，通过 X-Admin-User / X-Admin-Pass 认证
  static Future<AuthResult> _loginWeb(
    String serverUrl,
    String username,
    String password,
  ) async {
    final cleanUrl = _cleanUrl(serverUrl);
    final url = Uri.parse('$cleanUrl/admin/login');
    final client = http.Client();

    try {
      final response = await client.post(
        url,
        headers: {
          'X-Admin-User': username,
          'X-Admin-Pass': password,
        },
      );

      if (response.statusCode == 200) {
        final apiKey = _extractApiKey(response.body);
        if (apiKey != null && apiKey.isNotEmpty) {
          final prefs = await PreferencesService.getInstance();
          await prefs.setString(_tokenKey, apiKey);
          await prefs.setString(_serverUrlKey, cleanUrl);
          await prefs.setString('docker_api_key', apiKey);
          await prefs.setString('docker_api_url', cleanUrl);
          // 登录服务器凭据：不随切换活动服务器改变，
          // 服务器列表始终读写这台后端（跨 origin 共享同一份数据）
          await prefs.setString(_webBackendUrlKey, cleanUrl);
          await prefs.setString(_webBackendTokenKey, apiKey);
          return AuthResult.ok(apiKey);
        }
        return AuthResult.fail('响应中未找到 API Key');
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        return AuthResult.fail('用户名或密码错误');
      } else {
        return AuthResult.fail('服务器错误 (${response.statusCode})');
      }
    } catch (e) {
      return AuthResult.fail('无法连接到服务器: $e');
    } finally {
      client.close();
    }
  }

  /// 原生端登录：POST /api/auth（Portainer 标准）
  static Future<AuthResult> _loginNative(
    String serverUrl,
    String username,
    String password,
    bool ignoreSsl,
  ) async {
    final cleanUrl = _cleanUrl(serverUrl);
    final authUrl = Uri.parse('$cleanUrl/api/auth');
    final client = HttpHelper.createClient(ignoreSsl: ignoreSsl);

    try {
      final response = await client.post(
        authUrl,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final token = data['jwt'] as String?;
        if (token != null && token.isNotEmpty) {
          final prefs = await PreferencesService.getInstance();
          await prefs.setString(_tokenKey, token);
          await prefs.setString(_serverUrlKey, cleanUrl);
          await prefs.setString('docker_api_key', token);
          await prefs.setString('docker_api_url', cleanUrl);
          await prefs.setString('docker_ignore_ssl', ignoreSsl.toString());
          return AuthResult.ok(token);
        }
        return AuthResult.fail('响应中未找到认证令牌');
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        return AuthResult.fail('用户名或密码错误');
      } else {
        String detail = '服务器错误 (${response.statusCode})';
        try {
          final data = json.decode(response.body);
          if (data is Map && data.containsKey('message')) {
            detail = data['message'].toString();
          }
        } catch (_) {}
        return AuthResult.fail(detail);
      }
    } catch (e) {
      return AuthResult.fail('无法连接到服务器: $e');
    } finally {
      client.close();
    }
  }

  /// 从响应中提取 API Key，兼容多种返回格式
  static String? _extractApiKey(String body) {
    try {
      final data = json.decode(body);
      if (data is Map<String, dynamic>) {
        if (data.containsKey('key')) return data['key']?.toString();
        if (data.containsKey('apiKey')) return data['apiKey']?.toString();
        if (data.containsKey('token')) return data['token']?.toString();
        if (data.containsKey('api_key')) return data['api_key']?.toString();
      }
    } catch (_) {}
    // 纯文本格式：响应体直接就是 key
    final trimmed = body.trim();
    if (trimmed.isNotEmpty && !trimmed.contains('{') && !trimmed.contains('<')) {
      return trimmed;
    }
    return null;
  }

  static String _cleanUrl(String serverUrl) {
    return serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
  }

  /// 检查是否已登录（web 端使用）。
  ///
  /// 仅凭 token 存在不足以保证登录态：浏览器可能残留过期/被删除/其他
  /// 实例的 API Key（如访问新部署实例时旧 token 仍留在 localStorage），
  /// 直接放行会进入概览页后所有请求 401，页面直接显示
  /// "Invalid API Key or Admin Credentials" 报错。因此这里额外用轻量
  /// 请求验证 token 有效性，无效（401/403）时自动清除凭据回登录页。
  static Future<bool> isLoggedIn({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!_isWeb) return true;
    final prefs = await PreferencesService.getInstance();
    final token = prefs.getString(_tokenKey);
    final url = prefs.getString(_serverUrlKey);
    if (token == null || token.isEmpty || url == null || url.isEmpty) {
      return false;
    }
    final valid = await verifyToken(url, token, timeout: timeout);
    if (!valid) {
      // 凭据无效：清除全部认证信息，避免残留 token 反复触发 401
      await logout();
    }
    return valid;
  }

  /// 通过轻量请求验证 API Key 是否有效（登录态检查用）。
  ///
  /// 仅 401/403（凭据无效）返回 false；其他状态码与网络异常返回 true
  /// （保守视为已登录，避免临时网络故障把用户踢回登录页）。请求带
  /// 超时，慢网络下登录页最多等待 [verifyTimeout] 后进入主界面。
  @visibleForTesting
  static Future<bool> verifyToken(
    String serverUrl,
    String token, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final client = debugHttpClient ?? http.Client();
    try {
      final response = await client
          .get(
            Uri.parse('${_cleanUrl(serverUrl)}/admin/servers'),
            headers: {
              'x-api-key': token,
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(timeout);
      return response.statusCode == 200;
    } on Exception {
      return true; // 网络异常：保守视为已登录
    } finally {
      if (debugHttpClient == null) client.close();
    }
  }

  /// 获取存储的认证令牌（供 DockerService 使用）
  static Future<String?> getToken() async {
    final prefs = await PreferencesService.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// 获取存储的服务器 URL
  static Future<String?> getServerUrl() async {
    final prefs = await PreferencesService.getInstance();
    return prefs.getString(_serverUrlKey);
  }

  /// 获取 API Key 列表（Web 端）
  static Future<List<Map<String, dynamic>>> getApiKeys() async {
    final prefs = await PreferencesService.getInstance();
    final serverUrl = prefs.getString(_serverUrlKey);
    final token = prefs.getString(_tokenKey);

    if (serverUrl == null || token == null) {
      throw Exception('未登录');
    }

    final cleanUrl = _cleanUrl(serverUrl);
    final url = Uri.parse('$cleanUrl/admin/keys');
    final client = http.Client();

    try {
      final response = await client.get(
        url,
        headers: {'x-api-key': token},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('获取 API Key 列表失败 (${response.statusCode})');
      }
    } finally {
      client.close();
    }
  }

  /// 创建 API Key（Web 端），key 为空时由后端自动生成
  static Future<Map<String, dynamic>> createApiKey({
    required String name,
    String? key,
    String? expiresAt,
  }) async {
    final prefs = await PreferencesService.getInstance();
    final serverUrl = prefs.getString(_serverUrlKey);
    final token = prefs.getString(_tokenKey);

    if (serverUrl == null || token == null) {
      throw Exception('未登录');
    }

    final cleanUrl = _cleanUrl(serverUrl);
    final url = Uri.parse('$cleanUrl/admin/keys');
    final client = http.Client();

    try {
      final body = <String, dynamic>{'name': name};
      if (key != null && key.isNotEmpty) {
        body['key'] = key;
      }
      if (expiresAt != null) {
        body['expires_at'] = expiresAt;
      }

      final response = await client.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('创建 API Key 失败 (${response.statusCode})');
      }
    } finally {
      client.close();
    }
  }

  /// 删除 API Key（Web 端）
  static Future<void> deleteApiKey(String keyId) async {
    final prefs = await PreferencesService.getInstance();
    final serverUrl = prefs.getString(_serverUrlKey);
    final token = prefs.getString(_tokenKey);

    if (serverUrl == null || token == null) {
      throw Exception('未登录');
    }

    final cleanUrl = _cleanUrl(serverUrl);
    final url = Uri.parse('$cleanUrl/admin/keys/$keyId');
    final client = http.Client();

    try {
      final response = await client.delete(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('删除 API Key 失败 (${response.statusCode})');
      }
    } finally {
      client.close();
    }
  }

  /// 修改当前 Web 管理员的密码。
  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final prefs = await PreferencesService.getInstance();
    final serverUrl = prefs.getString(_serverUrlKey);
    final token = prefs.getString(_tokenKey);

    if (serverUrl == null || token == null) {
      throw Exception('未登录');
    }

    final url = Uri.parse('${_cleanUrl(serverUrl)}/admin/password');
    final client = http.Client();

    try {
      final response = await client.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'current_password': currentPassword,
          'new_password': newPassword,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        String detail = '修改密码失败 (${response.statusCode})';
        try {
          final data = json.decode(response.body);
          if (data is Map && data['message'] != null) {
            detail = data['message'].toString();
          } else if (data is Map && data['detail'] != null) {
            detail = data['detail'].toString();
          }
        } catch (_) {}
        throw Exception(detail);
      }
    } finally {
      client.close();
    }
  }

  /// 获取 SMTP 邮件配置。
  static Future<Map<String, dynamic>> getEmailConfig() async {
    final prefs = await PreferencesService.getInstance();
    final serverUrl = prefs.getString(_serverUrlKey);
    final token = prefs.getString(_tokenKey);

    if (serverUrl == null || token == null) {
      throw Exception('未登录');
    }

    final url = Uri.parse('${_cleanUrl(serverUrl)}/admin/email/config');
    final client = http.Client();

    try {
      final response = await client.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'x-api-key': token,
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        String detail = '获取邮件配置失败 (${response.statusCode})';
        try {
          final data = json.decode(response.body);
          if (data is Map && data['message'] != null) {
            detail = data['message'].toString();
          } else if (data is Map && data['detail'] != null) {
            detail = data['detail'].toString();
          }
        } catch (_) {}
        throw Exception(detail);
      }
    } finally {
      client.close();
    }
  }

  /// 保存 SMTP 邮件配置。
  static Future<void> saveSmtpConfig({
    required String host,
    required int port,
    required String username,
    String password = '',
    required String fromEmail,
    String fromName = 'Mobile Portainer',
    bool useSsl = false,
    bool useStarttls = true,
    int timeout = 10,
  }) async {
    final prefs = await PreferencesService.getInstance();
    final serverUrl = prefs.getString(_serverUrlKey);
    final token = prefs.getString(_tokenKey);

    if (serverUrl == null || token == null) {
      throw Exception('未登录');
    }

    final url = Uri.parse('${_cleanUrl(serverUrl)}/admin/email/config');
    final client = http.Client();

    try {
      final response = await client.put(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'x-api-key': token,
        },
        body: json.encode({
          'host': host,
          'port': port,
          'username': username,
          'password': password,
          'from_email': fromEmail,
          'from_name': fromName,
          'use_ssl': useSsl,
          'use_starttls': useStarttls,
          'timeout': timeout,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        String detail = '保存 SMTP 配置失败 (${response.statusCode})';
        try {
          final data = json.decode(response.body);
          if (data is Map && data['message'] != null) {
            detail = data['message'].toString();
          } else if (data is Map && data['detail'] != null) {
            detail = data['detail'].toString();
          }
        } catch (_) {}
        throw Exception(detail);
      }
    } finally {
      client.close();
    }
  }

  /// 发送测试邮件到指定邮箱。
  static Future<void> sendTestEmail({
    required String toEmail,
  }) async {
    final prefs = await PreferencesService.getInstance();
    final serverUrl = prefs.getString(_serverUrlKey);
    final token = prefs.getString(_tokenKey);

    if (serverUrl == null || token == null) {
      throw Exception('未登录');
    }

    final url = Uri.parse('${_cleanUrl(serverUrl)}/admin/email/send');
    final client = http.Client();

    try {
      final response = await client.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'x-api-key': token,
        },
        body: json.encode({
          'recipients': [toEmail],
          'subject': '测试邮件',
          'text_body': '这是一封测试邮件',
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        String detail = '发送测试邮件失败 (${response.statusCode})';
        try {
          final data = json.decode(response.body);
          if (data is Map && data['message'] != null) {
            detail = data['message'].toString();
          } else if (data is Map && data['detail'] != null) {
            detail = data['detail'].toString();
          }
        } catch (_) {}
        throw Exception(detail);
      }
    } finally {
      client.close();
    }
  }

  /// 获取 AI API 供应商配置列表。
  static Future<List<dynamic>> getAiProviders() async {
    final prefs = await PreferencesService.getInstance();
    final serverUrl = prefs.getString(_serverUrlKey);
    final token = prefs.getString(_tokenKey);

    if (serverUrl == null || token == null) {
      throw Exception('未登录');
    }

    final url = Uri.parse('${_cleanUrl(serverUrl)}/admin/ai-providers');
    final client = http.Client();

    try {
      final response = await client.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'x-api-key': token,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) return data;
        throw Exception('响应格式不正确');
      } else {
        throw Exception('获取 AI 供应商配置失败 (${response.statusCode})');
      }
    } finally {
      client.close();
    }
  }

  /// 获取 Hermes 接入状态（enabled / base_url / model / api_key_configured / test）。
  static Future<Map<String, dynamic>> getHermesStatus() async {
    final prefs = await PreferencesService.getInstance();
    final serverUrl = prefs.getString(_serverUrlKey);
    final token = prefs.getString(_tokenKey);

    if (serverUrl == null || token == null) {
      throw Exception('未登录');
    }

    final url = Uri.parse('${_cleanUrl(serverUrl)}/admin/hermes/status');
    final client = http.Client();

    try {
      final response = await client.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'x-api-key': token,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic>) return data;
        throw Exception('响应格式不正确');
      } else {
        throw Exception('获取 Hermes 状态失败 (${response.statusCode})');
      }
    } finally {
      client.close();
    }
  }

  /// 保存 Hermes 接入配置（baseUrl 空 = 禁用接入；apiKey 空 = 不修改已存储的 Key）。
  ///
  /// 返回保存后的状态（enabled / source / base_url / model / api_key_configured / test）。
  static Future<Map<String, dynamic>> saveHermesConfig({
    required String baseUrl,
    String apiKey = '',
    String model = '',
  }) async {
    final prefs = await PreferencesService.getInstance();
    final serverUrl = prefs.getString(_serverUrlKey);
    final token = prefs.getString(_tokenKey);

    if (serverUrl == null || token == null) {
      throw Exception('未登录');
    }

    final url = Uri.parse('${_cleanUrl(serverUrl)}/admin/hermes/config');
    final client = http.Client();

    try {
      final response = await client.put(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'x-api-key': token,
        },
        body: json.encode({
          'base_url': baseUrl,
          'api_key': apiKey,
          'model': model,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic>) return data;
        throw Exception('响应格式不正确');
      } else {
        throw Exception('保存 Hermes 配置失败 (${response.statusCode})');
      }
    } finally {
      client.close();
    }
  }

  /// 创建 AI API 供应商。
  static Future<Map<String, dynamic>> createAiProvider({
    required String name,
    required String providerType,
    required String baseUrl,
    required String apiKey,
    String defaultModel = '',
    bool enabled = true,
  }) async {
    final prefs = await PreferencesService.getInstance();
    final serverUrl = prefs.getString(_serverUrlKey);
    final token = prefs.getString(_tokenKey);

    if (serverUrl == null || token == null) {
      throw Exception('未登录');
    }

    final url = Uri.parse('${_cleanUrl(serverUrl)}/admin/ai-providers');
    final client = http.Client();

    try {
      final response = await client.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'x-api-key': token,
        },
        body: json.encode({
          'name': name,
          'provider_type': providerType,
          'base_url': baseUrl,
          'api_key': apiKey,
          'default_model': defaultModel,
          'enabled': enabled,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        String detail = '创建供应商失败 (${response.statusCode})';
        try {
          final data = json.decode(response.body);
          if (data is Map && data['detail'] != null) {
            detail = data['detail'].toString();
          }
        } catch (_) {}
        throw Exception(detail);
      }
    } finally {
      client.close();
    }
  }

  /// 更新 AI API 供应商；apiKey 传空字符串表示不修改已存储的 Key。
  static Future<Map<String, dynamic>> updateAiProvider({
    required String id,
    String? name,
    String? providerType,
    String? baseUrl,
    String apiKey = '',
    String? defaultModel,
    bool? enabled,
  }) async {
    final prefs = await PreferencesService.getInstance();
    final serverUrl = prefs.getString(_serverUrlKey);
    final token = prefs.getString(_tokenKey);

    if (serverUrl == null || token == null) {
      throw Exception('未登录');
    }

    final url = Uri.parse('${_cleanUrl(serverUrl)}/admin/ai-providers/$id');
    final client = http.Client();

    try {
      final response = await client.put(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'x-api-key': token,
        },
        body: json.encode({
          if (name != null) 'name': name,
          if (providerType != null) 'provider_type': providerType,
          if (baseUrl != null) 'base_url': baseUrl,
          if (apiKey.isNotEmpty) 'api_key': apiKey,
          if (defaultModel != null) 'default_model': defaultModel,
          if (enabled != null) 'enabled': enabled,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        String detail = '更新供应商失败 (${response.statusCode})';
        try {
          final data = json.decode(response.body);
          if (data is Map && data['detail'] != null) {
            detail = data['detail'].toString();
          }
        } catch (_) {}
        throw Exception(detail);
      }
    } finally {
      client.close();
    }
  }

  /// 删除 AI API 供应商。
  static Future<void> deleteAiProvider({required String id}) async {
    final prefs = await PreferencesService.getInstance();
    final serverUrl = prefs.getString(_serverUrlKey);
    final token = prefs.getString(_tokenKey);

    if (serverUrl == null || token == null) {
      throw Exception('未登录');
    }

    final url = Uri.parse('${_cleanUrl(serverUrl)}/admin/ai-providers/$id');
    final client = http.Client();

    try {
      final response = await client.delete(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'x-api-key': token,
        },
      );

      if (response.statusCode != 200) {
        throw Exception('删除供应商失败 (${response.statusCode})');
      }
    } finally {
      client.close();
    }
  }

  /// 测试 AI API 供应商连接，返回 {ok, message}。
  static Future<Map<String, dynamic>> testAiProvider({required String id}) async {
    final prefs = await PreferencesService.getInstance();
    final serverUrl = prefs.getString(_serverUrlKey);
    final token = prefs.getString(_tokenKey);

    if (serverUrl == null || token == null) {
      throw Exception('未登录');
    }

    final url = Uri.parse('${_cleanUrl(serverUrl)}/admin/ai-providers/$id/test');
    final client = http.Client();

    try {
      final response = await client.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'x-api-key': token,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map) return Map<String, dynamic>.from(data);
        throw Exception('响应格式不正确');
      } else {
        throw Exception('测试连接失败 (${response.statusCode})');
      }
    } finally {
      client.close();
    }
  }

  /// 获取当前用户个人信息。
  static Future<Map<String, dynamic>> getProfile() async {
    final prefs = await PreferencesService.getInstance();
    final serverUrl = prefs.getString(_serverUrlKey);
    final token = prefs.getString(_tokenKey);

    if (serverUrl == null || token == null) {
      throw Exception('未登录');
    }

    final url = Uri.parse('${_cleanUrl(serverUrl)}/admin/profile');
    final client = http.Client();

    try {
      final response = await client.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'x-api-key': token,
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        String detail = '获取个人信息失败 (${response.statusCode})';
        try {
          final data = json.decode(response.body);
          if (data is Map && data['message'] != null) {
            detail = data['message'].toString();
          } else if (data is Map && data['detail'] != null) {
            detail = data['detail'].toString();
          }
        } catch (_) {}
        throw Exception(detail);
      }
    } finally {
      client.close();
    }
  }

  /// 更新用户个人信息（绑定/修改邮箱）。
  static Future<Map<String, dynamic>> updateProfile({
    String? email,
  }) async {
    final prefs = await PreferencesService.getInstance();
    final serverUrl = prefs.getString(_serverUrlKey);
    final token = prefs.getString(_tokenKey);

    if (serverUrl == null || token == null) {
      throw Exception('未登录');
    }

    final url = Uri.parse('${_cleanUrl(serverUrl)}/admin/profile');
    final client = http.Client();

    try {
      final body = <String, dynamic>{};
      if (email != null) {
        body['email'] = email;
      }

      final response = await client.put(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'x-api-key': token,
        },
        body: json.encode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        if (response.body.isNotEmpty) {
          return json.decode(response.body) as Map<String, dynamic>;
        }
        return <String, dynamic>{};
      } else {
        String detail = '更新个人信息失败 (${response.statusCode})';
        try {
          final data = json.decode(response.body);
          if (data is Map && data['message'] != null) {
            detail = data['message'].toString();
          } else if (data is Map && data['detail'] != null) {
            detail = data['detail'].toString();
          }
        } catch (_) {}
        throw Exception(detail);
      }
    } finally {
      client.close();
    }
  }

  /// 登出，清除认证信息
  static Future<void> logout() async {
    final prefs = await PreferencesService.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_serverUrlKey);
    await prefs.remove(_webBackendUrlKey);
    await prefs.remove(_webBackendTokenKey);
    await prefs.remove('docker_api_key');
    await prefs.remove('docker_api_url');
  }
}
