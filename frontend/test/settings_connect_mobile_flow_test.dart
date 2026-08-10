import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/settings_screen.dart';
import 'package:mobile_portainer_flutter_module/services/connect_service.dart';
import 'test_utils.dart';

/// 移动端(io 分支)"网页授权添加"对话框流程测试。
///
/// VM 中 kIsWeb 恒为 false,Web 端入口不可达,通过公开方法直接打开
/// 对话框验证 io 分支:探测成功 → 展示跳转确认 → 点击跳转不崩溃
/// (url_launcher 无平台通道,ConnectPlatform.redirect 吞异常返回 false)。
void main() {
  tearDown(() {
    SharedPreferences.setMockInitialValues({});
    ConnectService.debugHttpClient = null;
  });

  testWidgets('移动端探测成功展示跳转提示并安全执行跳转', (tester) async {
    SharedPreferences.setMockInitialValues({});

    PackageInfo.setMockInitialValues(
      appName: 'Test',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'test-signature',
    );

    // 目标服务器支持 /connect:探测返回 enabled=true
    ConnectService.debugHttpClient = MockClient((req) async {
      if (req.url.path.endsWith('/connect/capabilities')) {
        return http.Response(jsonEncode({'enabled': true}), 200);
      }
      if (req.url.path.endsWith('/connect/register')) {
        return http.Response(
            jsonEncode({'client_id': 'client-test', 'client_name': 'x'}), 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(buildTestApp(home: const SettingsScreen()));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final state = tester.state<SettingsScreenState>(find.byType(SettingsScreen));
    state.showConnectAddDialog();
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 输入目标服务器 URL
    await tester.enterText(find.byType(TextField), 'http://10.0.0.1:9000');
    await tester.pumpAndSettle();

    // 点击探测按钮(非 isProbed 状态下的主按钮,label 为 Continue)
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 探测成功:展示目标服务器卡片 + 移动端跳转提示
    expect(find.text('http://10.0.0.1:9000'), findsWidgets);
    expect(find.textContaining('system browser'), findsOneWidget);

    // 点击确认跳转:VM 无 url_launcher 平台通道,应吞异常返回而非崩溃
    // (FilledButton.icon 的 runtimeType 非 FilledButton,直接按文本点击)
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
  });
}
