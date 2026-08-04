import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/dashboard_screen.dart';
import 'package:mobile_portainer_flutter_module/services/server_list_storage.dart';
import 'test_utils.dart';

/// 复现测试：Web 端概览页只显示一个服务器。
///
/// 背景：44b3ff2 将 Web 端服务器列表改存后端数据库（/admin/servers），设置页
/// 已改用 ServerListStorage 读写；但概览页（DashboardScreen）仍直接从
/// SharedPreferences（Web 端即 localStorage 旧缓存）读取 server_list，
/// 导致同一实例在 http://10.0.0.169:8080 添加的服务器，访问
/// https://home.chenkaidi.top:507 时设置页显示、概览页不显示。
///
/// VM 测试中 PlatformDetector.isWeb 恒为 false，通过 serverListStorageFactory
/// 注入 forceWeb: true 的 ServerListStorage，配合 debugHttpClient mock 后端
/// /admin/servers 接口，模拟"localStorage 旧缓存 1 个、后端数据库 2 个"的场景。
void main() {
  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
    ServerListStorage.debugHttpClient = null;
  });

  testWidgets('Web 端概览页从后端加载服务器列表（跨 origin 共享）', (tester) async {
    // localStorage 中仅旧缓存 1 个服务器（提交 44b3ff2 之前保存）；
    // 后端数据库中有 2 个服务器（用户在 http://10.0.0.169:8080 入口添加）
    SharedPreferences.setMockInitialValues({
      'server_list': jsonEncode([
        {
          'name': 'Old Home Server',
          'url': 'http://127.0.0.1:1',
          'apiKey': 'old-key',
          'ignoreSsl': 'false',
        },
      ]),
      'docker_api_url': 'http://127.0.0.1:1',
      'docker_auth_server_url': 'https://home.chenkaidi.top:507',
      'docker_auth_token': 'token-1',
    });

    ServerListStorage.debugHttpClient = MockClient((request) async {
      expect(request.url.path, '/admin/servers');
      return http.Response(
        jsonEncode([
          {
            'name': 'Home Server',
            'url': 'http://127.0.0.1:1',
            'apiKey': 'key-1',
            'ignoreSsl': 'false',
          },
          {
            'name': 'Second Server',
            'url': 'http://127.0.0.1:2',
            'apiKey': 'key-2',
            'ignoreSsl': 'false',
          },
        ]),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(buildTestApp(
      home: Scaffold(
        body: DashboardScreen(
          serverListStorageFactory: () => ServerListStorage(forceWeb: true),
        ),
      ),
    ));
    // _loadData 含多次 await，多 pump 几次等待加载完成
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // 每个服务器渲染一个 Card
    expect(
      find.byType(Card),
      findsNWidgets(2),
      reason: '概览页应从后端加载全部服务器，而不是只读 localStorage 旧缓存',
    );

    // 卸载 widget 以触发 dispose 取消重试 Timer
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
