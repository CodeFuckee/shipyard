import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_portainer_flutter_module/screens/login_screen.dart';
import 'test_utils.dart';

/// 复现 bug:登录界面使用 Bitwarden/vaultwarden 密码管理器自动填充时报
/// "Did not autofill"。根因是登录输入框未设置 autofillHints,Flutter Web
/// 渲染出的 <input> 没有 autocomplete 属性,密码管理器无法识别登录表单。
void main() {
  Future<Map<String, TextField>> pumpLoginScreen(
      WidgetTester tester) async {
    await tester.pumpWidget(buildTestApp(home: const LoginScreen()));
    await tester.pumpAndSettle();

    // TextFormField 不暴露 autofillHints/obscureText,通过其内部构建的
    // TextField 检查实际传给底层输入框的属性
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    return {
      'username': fields.firstWhere((f) => !f.obscureText),
      'password': fields.firstWhere((f) => f.obscureText),
    };
  }

  testWidgets('用户名输入框声明 username autofillHint,密码管理器才能识别',
      (tester) async {
    final fields = await pumpLoginScreen(tester);

    final hints = fields['username']!.autofillHints;
    expect(hints, isNotNull, reason: '用户名输入框缺少 autofillHints,Bitwarden 无法识别');
    expect(hints, contains(AutofillHints.username));
  });

  testWidgets('密码输入框声明 password autofillHint,密码管理器才能识别',
      (tester) async {
    final fields = await pumpLoginScreen(tester);

    final hints = fields['password']!.autofillHints;
    expect(hints, isNotNull, reason: '密码输入框缺少 autofillHints,Bitwarden 无法识别');
    expect(hints, contains(AutofillHints.password));
  });
}
