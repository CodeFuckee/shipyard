import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/settings_screen.dart';
import 'test_utils.dart';

void main() {
  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('切换服务器后 docker_auth_* 凭据同步更新为新服务器', (tester) async {
    // 模拟 Web 端登录服务器 A 后添加了服务器 B 的场景：
    // docker_auth_server_url / docker_auth_token 仍是登录时 A 的值，
    // 服务器列表包含 A（激活）和 B
    SharedPreferences.setMockInitialValues({
      'docker_auth_token': 'key-of-server-A',
      'docker_auth_server_url': 'http://server-a:8000',
      'docker_api_key': 'key-of-server-A',
      'docker_api_url': 'http://server-a:8000',
      'docker_ignore_ssl': 'false',
      'server_list': jsonEncode([
        {
          'name': 'Server A',
          'url': 'http://server-a:8000',
          'apiKey': 'key-of-server-A',
          'ignoreSsl': 'false',
        },
        {
          'name': 'Server B',
          'url': 'http://server-b:8000',
          'apiKey': 'key-of-server-B',
          'ignoreSsl': 'false',
        },
      ]),
    });

    PackageInfo.setMockInitialValues(
      appName: 'Test',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'test-signature',
    );

    await tester.pumpWidget(buildTestApp(home: const SettingsScreen()));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 点击服务器 B 切换到新服务器
    await tester.tap(find.text('Server B'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 切换后 Web 端认证凭据必须指向新服务器 B，
    // 否则设置页 API Key 管理仍显示旧服务器 A 的 key，
    // 用户复制后填入 B 会导致 B 的 /info 请求返回 401
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('docker_auth_server_url'), 'http://server-b:8000');
    expect(prefs.getString('docker_auth_token'), 'key-of-server-B');
  });
}
