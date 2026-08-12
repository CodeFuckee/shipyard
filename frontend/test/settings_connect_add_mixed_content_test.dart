import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/settings_screen.dart';
import 'test_utils.dart';

/// 复现测试:网页授权添加对话框中,mixed content 提示(提示条)文案超长,
/// 完整显示不被截断;提示条随输入实时显示/隐藏(issue #19 配套)。
///
/// 注意:提示为输入框下方固定高度占位 + Opacity 显隐的独立提示条
/// (子树恒挂载,Web 端提示条挂载/卸载会触发引擎失焦 bug,issue #19)。
void main() {
  testWidgets('mixed content 提示条完整显示,并随输入实时显示/隐藏', (tester) async {
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

    // flutter test 中 kIsWeb 恒为 false,通过公开方法注入 https 源场景。
    // 对话框默认预填 http:// → 打开即显示 mixed content 提示。
    final state = tester
        .state<SettingsScreenState>(find.byType(SettingsScreen));
    state.showConnectAddDialog(sourceIsHttpsOverride: true);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 提示条文案(恒在树中,Opacity 控制显隐)
    final hintText = find.textContaining('mixed content');
    expect(hintText, findsOneWidget,
        reason: '提示条应存在于对话框(https 源 + http 目标)');

    double hintOpacity() {
      // 找到包裹提示条文本的最近 Opacity
      final opacity = tester.widget<Opacity>(
        find.ancestor(of: hintText, matching: find.byType(Opacity)).first,
      );
      return opacity.opacity;
    }

    // 1. 打开即显示(预填 http://,https 源)
    expect(hintOpacity(), 1.0, reason: 'https 源 + http 目标应显示提示');
    // 提示条完整渲染:文本不限行数,高度应远大于单行省略
    // (issue #19 前 errorText 单行截断问题)。
    final size = tester.getSize(hintText);
    expect(size.height, greaterThan(24),
        reason: 'mixed content 提示被截断为单行,完整文案未显示');

    // 2. 输入 https:// 目标 → 提示隐藏,继续按钮恢复可用
    final continueFinder =
        find.widgetWithText(FilledButton, 'Continue');
    // 提示显示时(第 1 步),"继续"按钮禁用
    expect(tester.widget<FilledButton>(continueFinder).onPressed, isNull,
        reason: 'mixed content 提示时继续按钮应禁用');
    await tester.enterText(find.byType(TextField), 'https://192.168.1.10:9000');
    await tester.pumpAndSettle();
    expect(hintOpacity(), 0.0, reason: 'https 目标不触发 mixed content,提示应隐藏');
    expect(tester.widget<FilledButton>(continueFinder).onPressed, isNotNull,
        reason: 'https 目标无 mixed content,继续按钮应可用');

    // 3. 删除到 http:// 边界 → 提示重新显示
    await tester.enterText(find.byType(TextField), 'http://192.168.1.10:9000');
    await tester.pumpAndSettle();
    expect(hintOpacity(), 1.0, reason: 'http 目标触发 mixed content,提示应显示');

    // 4. 输入框本身不承载错误提示(稳定结构,不随输入变化)
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.decoration?.errorText, isNull,
        reason: '提示已移出输入框 errorText,输入框结构不随输入变化');
  });
}
