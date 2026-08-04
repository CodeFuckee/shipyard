import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/settings_screen.dart';
import 'test_utils.dart';

Future<void> _openAddServerDialog(WidgetTester tester) async {
  // 空列表时设置页显示"Add Server"空状态，点击后弹出添加方式底部面板
  await tester.tap(find.text('Add Server'));
  await tester.pumpAndSettle(const Duration(seconds: 1));
  // 选择手动输入
  await tester.tap(find.text('Manual Input'));
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

void main() {
  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('添加服务器时 API Key 为空禁止保存并提示', (tester) async {
    SharedPreferences.setMockInitialValues({});

    PackageInfo.setMockInitialValues(
      appName: 'Test',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'test-signature',
    );

    await tester.pumpWidget(buildTestApp(home: const SettingsScreen()));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await _openAddServerDialog(tester);

    // 填写名称和 URL，API Key 留空
    await tester.enterText(find.byType(TextField).at(0), 'Server B');
    await tester.enterText(find.byType(TextField).at(1), 'http://server-b:8000');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 提示 API Key 必填，且对话框未关闭
    expect(find.text('API Key is required'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('点击测试连接按钮显示连接结果', (tester) async {
    SharedPreferences.setMockInitialValues({});

    PackageInfo.setMockInitialValues(
      appName: 'Test',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'test-signature',
    );

    await tester.pumpWidget(buildTestApp(home: const SettingsScreen()));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await _openAddServerDialog(tester);

    // 填写名称、URL 和 API Key
    await tester.enterText(find.byType(TextField).at(0), 'Server B');
    await tester.enterText(find.byType(TextField).at(1), 'http://server-b:8000');
    await tester.enterText(find.byType(TextField).at(2), 'key-of-server-B');

    // 测试环境网络请求被 flutter_test mock 为 400，应显示连接失败提示
    await tester.tap(find.text('Test Connection'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.textContaining('Connection failed'), findsOneWidget);
  });
}
