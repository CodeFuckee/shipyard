import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/settings_screen.dart';
import 'test_utils.dart';

/// 防回归测试(issue #19):网页授权添加服务器对话框中,输入 docker api 地址时
/// 输入框必须保持焦点,可连续输入/删除。
///
/// 根因:onChanged 每次击键无条件重建整个对话框,Web 端含 TextField 的
/// 子树重建会导致输入框失焦。修复:isMixedContent 改为 ValueNotifier
/// 局部更新(提示条 + 按钮禁用态),输入过程中 TextField 永不重建。
void main() {
  testWidgets('网页授权添加对话框:连续输入/删除字符时输入框保持焦点', (tester) async {
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

    // flutter test 中 kIsWeb 恒为 false,通过公开方法直接打开对话框。
    // https 源场景下输入 http 目标会触发 mixed content 提示状态翻转
    // (修复前每次翻转都重建对话框,Web 端失焦)。
    final state = tester
        .state<SettingsScreenState>(find.byType(SettingsScreen));
    state.showConnectAddDialog(sourceIsHttpsOverride: true);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final urlField = find.byType(TextField);
    expect(urlField, findsOneWidget);

    final editableFinder = find.descendant(
      of: urlField,
      matching: find.byType(EditableText),
    );
    final editable = tester.widget<EditableText>(editableFinder);
    final focusNode = editable.focusNode;
    expect(focusNode.hasFocus, isTrue, reason: '对话框打开后输入框应自动聚焦');

    // 连续输入:每次字符变化触发 onChanged(修复前每次重建对话框)
    await tester.enterText(urlField, 'http://192.168.1.10:9000');
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue, reason: '输入字符后输入框失去焦点');

    // 连续删除字符(跨 http/https mixed content 状态翻转边界,
    // 修复前此瞬间 errorText 变化重建对话框)
    await tester.enterText(urlField, 'http://192.168.1.10:900');
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue, reason: '删除字符后输入框失去焦点');

    await tester.enterText(urlField, 'http://192.168.1.10:90');
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue, reason: '再次删除字符后输入框失去焦点');

    // 删除至 http:// 边界(http:/ 触发 Uri.tryParse 失败,
    // isMixedContent 翻转,修复前提示状态变化重建对话框)
    await tester.enterText(urlField, 'http:');
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue,
        reason: 'mixed content 状态翻转后输入框失去焦点');

    // 输入框结构稳定:onChanged 全程不重建输入框(errorText 恒为空,
    // 提示由独立提示条承载)
    final afterTyping = tester.widget<TextField>(urlField);
    expect(afterTyping.decoration?.errorText, isNull,
        reason: '输入变化不应重建输入框/修改其装饰结构');
  });
}
