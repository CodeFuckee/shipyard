import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mobile_portainer_flutter_module/screens/settings_screen.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'test_utils.dart';

/// 复现并验证 bug：
/// MainTabScreen 的底部导航栏是悬浮在 body 之上的浮层（Stack + Positioned
/// bottom: 0），而设置页 ListView 底部 padding 只有 32px，滚动到底后
/// 版本号徽章和构建时间行仍落在导航栏覆盖区域内，被"概览、容器"等 tab 挡住。
void main() {
  // 模拟手机屏幕 + iPhone 底部安全区（SafeArea bottom inset 34）。
  // 宽度取 600：过窄（400）会触发设置页下拉框既有的窄屏溢出，与本 bug 无关。
  const double screenWidth = 600;
  const double screenHeight = 800;
  const double safeBottom = 34;
  const double navBarHeight = 68;
  const double navBarTop = screenHeight - safeBottom - navBarHeight;

  Future<void> pumpSettingsWithFloatingNavBar(WidgetTester tester,
      {String buildTime = '2026-08-02 15:30:45'}) async {
    tester.view.physicalSize = const Size(screenWidth, screenHeight);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = FakeViewPadding(bottom: safeBottom);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
    });

    SharedPreferences.setMockInitialValues({
      'docker_auth_token': 'test-token',
      'docker_auth_server_url': 'http://test-server:9000',
      'docker_api_key': 'test-api-key',
      'docker_api_url': 'http://test-server:9000/api',
    });
    PackageInfo.setMockInitialValues(
      appName: 'Test',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'test-signature',
    );

    // 模拟 MainTabScreen 布局：body 之上悬浮底部导航栏
    await tester.pumpWidget(
      buildTestApp(
        home: Scaffold(
          body: Stack(
            children: [
              SettingsScreen(buildTime: buildTime),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _FakeBottomNavBar(height: navBarHeight),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 滚动列表到底部，露出页面末尾的版本号与构建时间
    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pumpAndSettle();
  }

  testWidgets('设置页底部版本号不被悬浮底部导航栏遮挡', (tester) async {
    await pumpSettingsWithFloatingNavBar(tester);

    final versionFinder = find.text('v1.0.0+1');
    expect(versionFinder, findsOneWidget);

    final rect = tester.getRect(versionFinder);
    // 版本号徽章完整处于导航栏覆盖区域之上
    expect(rect.bottom, lessThanOrEqualTo(navBarTop + 1),
        reason: '版本号徽章底部 ${rect.bottom} 应不高于导航栏顶部 $navBarTop');
  });

  testWidgets('设置页底部构建时间不被悬浮底部导航栏遮挡', (tester) async {
    await pumpSettingsWithFloatingNavBar(tester);

    final t = AppLocalizations.of(
        tester.element(find.byType(SettingsScreen)))!;
    final buildTimeFinder = find.textContaining(t.labelBuildTime);
    expect(buildTimeFinder, findsOneWidget);

    final rect = tester.getRect(buildTimeFinder);
    expect(rect.bottom, lessThanOrEqualTo(navBarTop + 1),
        reason: '构建时间行底部 ${rect.bottom} 应不高于导航栏顶部 $navBarTop');
  });
}

/// 模拟 MainTabScreen 悬浮底部导航栏的外层结构（SafeArea + 固定高度）。
class _FakeBottomNavBar extends StatelessWidget {
  const _FakeBottomNavBar({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: height,
        child: const ColoredBox(color: Colors.amber),
      ),
    );
  }
}
