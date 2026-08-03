import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_portainer_flutter_module/screens/login_screen.dart';
import 'test_utils.dart';

/// 登录界面自动填充(vaultwarden/Bitwarden)回归测试。
///
/// ohos 定制版 Flutter 引擎存在 autofill form 生命周期 bug:
/// TextInput.updateConfig 丢失 fields 配置导致引擎重建并拆散多字段 form,
/// 引发 Uncaught Error(main.dart.js:6326)与 Chrome a11y 警告。
/// 因此登录页不使用 autofillHints(引擎不再创建 autofill form),
/// Web 端改由 web/index.html 脚本手动注入 autocomplete 属性。
/// 此测试确保登录页不会重新引入 autofillHints。
void main() {
  Future<Map<String, TextField>> pumpLoginScreen(WidgetTester tester) async {
    await tester.pumpWidget(buildTestApp(home: const LoginScreen()));
    await tester.pumpAndSettle();

    // TextFormField 不暴露 autofillHints,通过其内部构建的
    // TextField 检查实际传给底层输入框的属性
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    return {
      'username': fields.firstWhere((f) => !f.obscureText),
      'password': fields.firstWhere((f) => f.obscureText),
    };
  }

  testWidgets('登录输入框不设置 autofillHints,规避引擎 autofill form 拆分 bug',
      (tester) async {
    final fields = await pumpLoginScreen(tester);

    expect(fields['username']!.autofillHints, isNull,
        reason: '用户名框不应设置 autofillHints:会触发 ohos 引擎 autofill form 重建 bug(Uncaught Error)');
    expect(fields['password']!.autofillHints, isNull,
        reason: '密码框不应设置 autofillHints:会触发 ohos 引擎 autofill form 重建 bug(Uncaught Error)');
  });
}
