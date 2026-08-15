import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/settings_screen.dart';
import 'test_utils.dart';

/// issue #33：删除设置页面配置外部 hermes 的选项。
///
/// 验收：设置页不再显示「Hermes 接入」配置入口；hermes 仅由部署环境的
/// 环境变量配置，调用容器内集成的 hermes。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Test',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'test-signature',
    );
    await tester.pumpWidget(buildTestApp(
      home: const SettingsScreen(),
      locale: const Locale('zh'),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  testWidgets('设置页不再显示外部 Hermes 配置入口', (tester) async {
    await pumpSettings(tester);

    expect(find.text('Hermes 接入'), findsNothing,
        reason: '外部 hermes 配置选项已删除，设置页不应再显示该入口');
    expect(find.textContaining('hermes'), findsNothing,
        reason: '设置页不应残留任何 hermes 配置相关文案');
  });

  testWidgets('设置页仍保留 AI 供应商配置入口（回退路径）', (tester) async {
    await pumpSettings(tester);

    expect(find.text('AI 供应商配置'), findsOneWidget,
        reason: 'AI 供应商配置（hermes 未配置时的回退路径）应保留');
  });
}
