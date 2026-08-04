import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/settings_screen.dart';
import 'package:mobile_portainer_flutter_module/widgets/action_sheet.dart';
import 'test_utils.dart';

/// 复现测试：非手机端（Web/桌面）不允许使用 showModalBottomSheet。
///
/// 规则（CLAUDE.md）：仅手机端（PlatformDetector.isAndroid / isIOS / isOhos
/// 之一为 true）才使用 showModalBottomSheet 弹出底部操作菜单；其他端
/// （Web、桌面等）一律使用 showDialog + AlertDialog 弹出居中对话框。
///
/// VM 测试环境中 PlatformDetector 解析为 io 实现，运行平台为 macOS/Linux，
/// isAndroid / isIOS / isOhos 全为 false —— 天然代表"非手机端"。
/// 当前代码无条件调用 showModalBottomSheet，以下断言应当失败。
void main() {
  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('非手机端 ActionSheet.show 弹出居中 AlertDialog 而非 BottomSheet',
      (tester) async {
    await tester.pumpWidget(buildTestApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => ActionSheet.show(
                context: context,
                header: const Text('Actions'),
                actions: const [
                  ActionItem(
                    label: 'Download',
                    icon: Icons.download,
                    color: Colors.blue,
                    actionCode: 'download',
                  ),
                  ActionItem(
                    label: 'Share',
                    icon: Icons.share,
                    color: Colors.green,
                    actionCode: 'share',
                  ),
                ],
                onAction: (code) {},
              ),
              child: const Text('Show Actions'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Show Actions'));
    await tester.pumpAndSettle();

    // 非手机端必须弹出居中 AlertDialog
    expect(find.byType(AlertDialog), findsOneWidget);
    // 不允许出现底部 BottomSheet
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('非手机端 ActionSheet 菜单项点击后触发回调', (tester) async {
    String? triggeredAction;
    await tester.pumpWidget(buildTestApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => ActionSheet.show(
                context: context,
                header: const Text('Actions'),
                actions: const [
                  ActionItem(
                    label: 'Download',
                    icon: Icons.download,
                    color: Colors.blue,
                    actionCode: 'download',
                  ),
                ],
                onAction: (code) => triggeredAction = code,
              ),
              child: const Text('Show Actions'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Show Actions'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(triggeredAction, 'download');
  });

  testWidgets('非手机端设置页"添加服务器"弹出居中对话框而非底部面板',
      (tester) async {
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

    // 空列表时设置页显示"Add Server"空状态，点击后弹出添加方式菜单
    await tester.tap(find.text('Add Server'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 非手机端必须弹出居中 AlertDialog，不允许底部 BottomSheet
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    // 对话框内应同时包含扫码与手动输入两个选项
    expect(find.text('Scan QR Code'), findsOneWidget);
    expect(find.text('Manual Input'), findsOneWidget);
  });
}
