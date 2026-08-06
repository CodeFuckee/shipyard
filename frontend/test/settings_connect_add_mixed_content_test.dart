import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/settings_screen.dart';
import 'test_utils.dart';

/// 复现测试:网页授权添加对话框中,mixed content 提示(errorText)文案超长,
/// 而 InputDecoration 未设置 errorMaxLines,Flutter 默认将超宽 errorText
/// 截断为单行省略号 → 提示文字显示不全。
void main() {
  testWidgets('mixed content 提示文字完整显示,不被截断为单行', (tester) async {
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

    // flutter test 中 kIsWeb 恒为 false,Web 端"网页授权添加"入口与
    // https 源判定均不可达,通过公开方法注入 https 源场景。
    // 对话框默认预填 http:// → 打开即触发 mixed content 提示。
    final state = tester
        .state<SettingsScreenState>(find.byType(SettingsScreen));
    state.showConnectAddDialog(sourceIsHttpsOverride: true);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 错误提示文案应完整渲染,而非单行省略截断。
    // 单行 bodySmall 高度约 16px,完整换行显示至少 2 行。
    final errorFinder = find.textContaining('mixed content');
    expect(errorFinder, findsOneWidget);
    final size = tester.getSize(errorFinder);
    expect(size.height, greaterThan(24),
        reason: 'mixed content 提示被截断为单行(errorMaxLines 未设置),'
            '完整文案未显示');
  });
}
