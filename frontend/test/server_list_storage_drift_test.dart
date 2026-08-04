import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/services/server_list_storage.dart';

/// 复现测试：切换活动服务器后，服务器列表的读写目标漂移到新服务器。
///
/// 用户报告：从服务器 A（10.0.0.169）通过网页授权添加服务器 B（10.0.0.122）后，
/// 服务器列表仍是 1 个，用授权签发的 key 访问 B 一直拉取失败。
///
/// 根因链路：
/// 1. 登录时 `docker_auth_server_url` / `docker_auth_token` 指向登录服务器 A；
/// 2. 授权添加后 `docker_api_url` / `docker_api_key` 切到新服务器 B；
/// 3. 用户点击 B 切换 → `_switchServer` 把 `docker_auth_server_url` /
///    `docker_auth_token` 也同步为 B（该设计意图是让 API Key 管理跟随
///    活动服务器）；
/// 4. 但 `ServerListStorage` 的读写也用这两个值作为目标 → 服务器列表
///    的存储位置从"登录服务器 A 的后端数据库"漂移到"被添加的服务器 B
///    的后端数据库"，A 上的列表再也读不到，刷新后只剩 B 自己的列表（1 个）。
void main() {
  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
    ServerListStorage.debugHttpClient = null;
  });

  const serverA = {
    'name': 'Server A',
    'url': 'http://server-a:8000',
    'apiKey': 'key-of-server-a',
    'ignoreSsl': 'false',
  };
  const serverB = {
    'name': 'Server B',
    'url': 'http://server-b:8000',
    'apiKey': 'key-of-server-b',
    'ignoreSsl': 'false',
  };
  // B 自己实例上的服务器列表（漂移后的错误读取目标）
  const serverBOnly = {
    'name': 'Default Server',
    'url': 'http://server-b:8000',
    'apiKey': 'key-of-server-b',
    'ignoreSsl': 'false',
  };

  /// 用户完整状态流后的 prefs：
  /// 登录服务器 A（web_backend_* 在登录时写入，不随切换改变；
  /// docker_auth_* 已被 _switchServer 覆盖为 B），
  /// 活动服务器 B（授权添加后自动切换）。
  Map<String, Object> driftedPrefs() => {
        'web_backend_url': 'http://server-a:8000',
        'web_backend_token': 'key-of-server-a',
        'docker_auth_token': 'key-of-server-b',
        'docker_auth_server_url': 'http://server-b:8000',
        'docker_api_key': 'key-of-server-b',
        'docker_api_url': 'http://server-b:8000',
        'docker_ignore_ssl': 'false',
        'server_list': jsonEncode([serverA, serverB]),
      };

  test('切换服务器后列表加载目标漂移：应从登录服务器加载，而非活动服务器', () async {
    SharedPreferences.setMockInitialValues(driftedPrefs());

    ServerListStorage.debugHttpClient = MockClient((request) async {
      if (request.url.host == 'server-a') {
        // 登录服务器 A 上的完整列表（用户在 A 上添加过 B）
        return http.Response(jsonEncode([serverA, serverB]), 200,
            headers: {'content-type': 'application/json'});
      }
      // 被添加的服务器 B 自己的列表——用户在 A 上添加的服务器不在其中
      return http.Response(jsonEncode([serverBOnly]), 200,
          headers: {'content-type': 'application/json'});
    });

    final servers = await ServerListStorage(forceWeb: true).load();

    expect(servers.length, 2,
        reason: '切换活动服务器不应改变服务器列表的存储位置；'
            '实际只加载到 ${servers.length} 个服务器（列表目标漂移到被添加的服务器）');
    expect(servers.map((s) => s['name']), contains('Server A'));
  });

  test('切换服务器后列表保存目标漂移：新添加的服务器应保存到登录服务器', () async {
    SharedPreferences.setMockInitialValues(driftedPrefs());

    late Uri capturedUri;
    ServerListStorage.debugHttpClient = MockClient((request) async {
      capturedUri = request.url;
      return http.Response(jsonEncode({'message': 'saved', 'count': 2}), 200,
          headers: {'content-type': 'application/json'});
    });

    await ServerListStorage(forceWeb: true).save([serverA, serverB]);

    expect(capturedUri.host, 'server-a',
        reason: '服务器列表必须保存到登录服务器 A 的后端，'
            '实际保存到 ${capturedUri.host}（漂移目标）');
  });

  test('授权添加后（活动服务器=B）列表保存目标应为登录服务器 A', () async {
    // 授权回调 `_addServerFromConnect` 后的真实状态：
    // docker_api_* 已切到 B，docker_auth_* 仍是登录时的 A（未切换过）
    SharedPreferences.setMockInitialValues({
      'web_backend_url': 'http://server-a:8000',
      'web_backend_token': 'key-of-server-a',
      'docker_auth_token': 'key-of-server-a',
      'docker_auth_server_url': 'http://server-a:8000',
      'docker_api_key': 'key-of-server-b',
      'docker_api_url': 'http://server-b:8000',
      'docker_ignore_ssl': 'false',
    });

    late Uri capturedUri;
    ServerListStorage.debugHttpClient = MockClient((request) async {
      capturedUri = request.url;
      if (request.method == 'GET') {
        return http.Response(jsonEncode([serverA]), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode({'message': 'saved', 'count': 2}), 200,
          headers: {'content-type': 'application/json'});
    });

    final servers = await ServerListStorage(forceWeb: true).load();
    servers.add(serverB);
    await ServerListStorage(forceWeb: true).save(servers);

    expect(capturedUri.host, 'server-a',
        reason: '授权添加的新服务器必须写入登录服务器 A 的列表，'
            '实际写入 ${capturedUri.host}');
  });

  test('存量用户（无 web_backend_*）回退 docker_auth_* 凭据', () async {
    // 修复功能上线前的部署：从未重新登录，无 web_backend_*。
    // 若未切换过服务器，docker_auth_* 仍指向登录服务器，应能正常读写。
    SharedPreferences.setMockInitialValues({
      'docker_auth_token': 'key-of-server-a',
      'docker_auth_server_url': 'http://server-a:8000',
      'docker_api_key': 'key-of-server-a',
      'docker_api_url': 'http://server-a:8000',
    });

    late Uri capturedUri;
    ServerListStorage.debugHttpClient = MockClient((request) async {
      capturedUri = request.url;
      if (request.method == 'GET') {
        return http.Response(jsonEncode([serverA]), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode({'message': 'saved', 'count': 1}), 200,
          headers: {'content-type': 'application/json'});
    });

    final servers = await ServerListStorage(forceWeb: true).load();
    expect(servers.length, 1, reason: '无 web_backend_* 时应回退 docker_auth_* 加载列表');

    await ServerListStorage(forceWeb: true).save(servers);
    expect(capturedUri.host, 'server-a',
        reason: '无 web_backend_* 时应回退 docker_auth_* 保存列表');
  });
}
