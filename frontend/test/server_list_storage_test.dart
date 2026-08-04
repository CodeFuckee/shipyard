import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/services/server_list_storage.dart';

/// 服务器列表存储测试。
///
/// 背景：Web 端服务器列表原存 localStorage，按 origin（协议+主机+端口）隔离，
/// 同一后端实例的不同访问入口（如 http://10.0.0.169:8080 与
/// https://home.chenkaidi.top:507）互不可见。修复后 Web 端存后端数据库，
/// 任何入口共享同一份数据。
///
/// VM 测试环境中 PlatformDetector.isWeb 恒为 false，通过 forceWeb: true
/// 强制走 Web 分支（后端 API），配合 debugHttpClient 注入 mock 验证请求行为。
void main() {
  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
    ServerListStorage.debugHttpClient = null;
  });

  const serverListJson = [
    {
      'name': 'Home Server',
      'url': 'http://10.0.0.169:9000',
      'apiKey': 'key-1',
      'ignoreSsl': 'false',
    },
  ];

  test('Web 端服务器列表从后端 API 加载（跨 origin 共享）', () async {
    SharedPreferences.setMockInitialValues({
      'docker_auth_server_url': 'https://home.chenkaidi.top:507',
      'docker_auth_token': 'token-1',
    });

    ServerListStorage.debugHttpClient = MockClient((request) async {
      expect(request.url.path, '/admin/servers');
      expect(request.headers['x-api-key'], 'token-1');
      return http.Response(
        jsonEncode(serverListJson),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final servers = await ServerListStorage(forceWeb: true).load();
    expect(servers.length, 1);
    expect(servers.first['name'], 'Home Server');
    expect(servers.first['apiKey'], 'key-1');
  });

  test('Web 端保存服务器列表调用后端 PUT API', () async {
    SharedPreferences.setMockInitialValues({
      'docker_auth_server_url': 'https://home.chenkaidi.top:507',
      'docker_auth_token': 'token-1',
    });

    late http.Request captured;
    ServerListStorage.debugHttpClient = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({'message': 'saved', 'count': 1}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await ServerListStorage(forceWeb: true).save(serverListJson);

    expect(captured.method, 'PUT');
    expect(captured.url.path, '/admin/servers');
    expect(jsonDecode(captured.body), serverListJson);
  });

  test('Web 端后端不可达时回退本地缓存', () async {
    SharedPreferences.setMockInitialValues({
      'docker_auth_server_url': 'https://home.chenkaidi.top:507',
      'docker_auth_token': 'token-1',
      'server_list': jsonEncode([
        {
          'name': 'Local Cache',
          'url': 'http://10.0.0.169:9000',
          'apiKey': 'cached-key',
          'ignoreSsl': 'false',
        },
      ]),
    });

    ServerListStorage.debugHttpClient = MockClient((request) async {
      return http.Response('Internal Server Error', 500);
    });

    final servers = await ServerListStorage(forceWeb: true).load();
    expect(servers.length, 1);
    expect(servers.first['name'], 'Local Cache');
  });

  test('Web 端未登录时不发起后端请求，直接使用本地存储', () async {
    // 仅本地缓存、无 docker_auth_* 凭据
    SharedPreferences.setMockInitialValues({
      'server_list': jsonEncode(serverListJson),
    });

    var called = false;
    ServerListStorage.debugHttpClient = MockClient((request) async {
      called = true;
      return http.Response('{}', 500);
    });

    final servers = await ServerListStorage(forceWeb: true).load();
    expect(called, false, reason: '未登录不应发起后端请求');
    expect(servers.length, 1);
  });

  test('原生端保存/加载使用本地 SharedPreferences', () async {
    final storage = ServerListStorage(); // forceWeb 默认 false（测试环境）

    await storage.save(serverListJson);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('server_list'), isNotNull);

    final servers = await storage.load();
    expect(servers, serverListJson);
  });
}
