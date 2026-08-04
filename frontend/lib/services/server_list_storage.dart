import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/platform_detector.dart';
import 'platform/preferences_service.dart';

/// 服务器列表存储。
///
/// Web 端服务器列表存后端数据库（`/admin/servers`），使同一实例的所有访问
/// 入口（不同 origin，如 `http://10.0.0.169:8080` 与
/// `https://home.chenkaidi.top:507`）共享同一份数据——浏览器 localStorage
/// 按 origin（协议+主机+端口）严格隔离，存本地会导致一个入口添加的服务器
/// 在另一个入口不可见。
/// 原生端（Android/iOS/macOS/ohos）存本地 SharedPreferences。
///
/// Web 端请求失败（未登录、网络错误、接口异常）时回退本地缓存，保证设置页
/// 始终可用；保存时后端失败同样落本地缓存，避免数据丢失。
class ServerListStorage {
  /// 测试注入的 http client（Web 分支使用）
  static http.Client? debugHttpClient;

  final bool _forceWeb;

  /// [forceWeb] 仅供测试：VM 测试环境中 [PlatformDetector.isWeb] 恒为 false，
  /// 通过该参数强制走 Web 分支验证后端存储逻辑。
  ServerListStorage({bool forceWeb = false}) : _forceWeb = forceWeb;

  bool get _isWeb => _forceWeb || PlatformDetector.isWeb;

  static const String _serverListKey = 'server_list';

  Future<List<Map<String, String>>> load() async {
    final prefs = await PreferencesService.getInstance();
    if (_isWeb) {
      final remote = await _loadFromServer(prefs);
      if (remote != null) return remote;
    }
    return _loadFromPrefs(prefs);
  }

  Future<void> save(List<Map<String, String>> servers) async {
    final prefs = await PreferencesService.getInstance();
    if (_isWeb) {
      final ok = await _saveToServer(prefs, servers);
      if (ok) return;
    }
    await _saveToPrefs(prefs, servers);
  }

  /// 从后端加载服务器列表；未登录或请求失败返回 null（走本地回退）。
  Future<List<Map<String, String>>?> _loadFromServer(
    PreferencesService prefs,
  ) async {
    final serverUrl = prefs.getString('docker_auth_server_url');
    final token = prefs.getString('docker_auth_token');
    if (serverUrl == null || serverUrl.isEmpty || token == null || token.isEmpty) {
      return null;
    }
    final client = _httpClient();
    try {
      final response = await client.get(
        Uri.parse('${_cleanUrl(serverUrl)}/admin/servers'),
        headers: {
          'x-api-key': token,
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List<dynamic>;
        return data.map((e) => Map<String, String>.from(e as Map)).toList();
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// 保存服务器列表到后端；未登录或请求失败返回 false（走本地回退）。
  Future<bool> _saveToServer(
    PreferencesService prefs,
    List<Map<String, String>> servers,
  ) async {
    final serverUrl = prefs.getString('docker_auth_server_url');
    final token = prefs.getString('docker_auth_token');
    if (serverUrl == null || serverUrl.isEmpty || token == null || token.isEmpty) {
      return false;
    }
    final client = _httpClient();
    try {
      final response = await client.put(
        Uri.parse('${_cleanUrl(serverUrl)}/admin/servers'),
        headers: {
          'x-api-key': token,
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(servers),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  List<Map<String, String>> _loadFromPrefs(PreferencesService prefs) {
    final jsonStr = prefs.getString(_serverListKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final decoded = jsonDecode(jsonStr) as List<dynamic>;
      return decoded.map((e) => Map<String, String>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveToPrefs(
    PreferencesService prefs,
    List<Map<String, String>> servers,
  ) async {
    await prefs.setString(_serverListKey, jsonEncode(servers));
  }

  http.Client _httpClient() => debugHttpClient ?? http.Client();

  static String _cleanUrl(String url) {
    return url.endsWith('/')
        ? url.substring(0, url.length - 1)
        : url;
  }
}
