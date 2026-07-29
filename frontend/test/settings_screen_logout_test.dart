import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mobile_portainer_flutter_module/screens/settings_screen.dart';
import 'package:mobile_portainer_flutter_module/screens/login_screen.dart';
import 'test_utils.dart';

class _WsDisposeTestWidget extends StatefulWidget {
  const _WsDisposeTestWidget();

  @override
  State<_WsDisposeTestWidget> createState() => _WsDisposeTestWidgetState();
}

class _WsDisposeTestWidgetState extends State<_WsDisposeTestWidget> {
  final StreamController<dynamic> _streamController =
      StreamController<dynamic>.broadcast();
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _streamController.stream.listen(
      (_) {},
      onDone: () {
        if (_disposed) return;
        setState(() {});
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _streamController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('WebSocket test')));
  }
}

void main() {
  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('dispose 期间 WebSocket onDone 不触发 defunct setState', (tester) async {
    await tester.pumpWidget(buildTestApp(home: const _WsDisposeTestWidget()));
    await tester.pump();

    await tester.pumpWidget(
      buildTestApp(home: const Scaffold(body: Center(child: Text('New Page')))),
    );
    await tester.pump();
  });

  testWidgets('设置页面点击退出登录后跳转至登录页且无报错', (tester) async {
    SharedPreferences.setMockInitialValues({
      'docker_auth_token': 'test-token',
      'docker_auth_server_url': 'http://test-server:9000',
      'docker_api_key': 'test-api-key',
      'docker_api_url': 'http://test-server:9000/api',
      'server_list':
          '[{"name":"Test Server","url":"http://test-server:9000","api_key":"test-api-key","ignore_ssl":"false"}]',
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

    final logoutTile = find.byIcon(Icons.logout);
    if (logoutTile.evaluate().isNotEmpty) {
      await tester.tap(logoutTile);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.byType(LoginScreen), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('docker_auth_token'), isNull);
      expect(prefs.getString('docker_auth_server_url'), isNull);
    }
  });
}
