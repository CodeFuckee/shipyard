import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/screens/main_tab_screen.dart';
import 'package:mobile_portainer_flutter_module/screens/home_screen.dart';
import 'test_utils.dart';

/// issue #18：底部导航栏的容器 tab 整合到资源页面，容器排在镜像页面前。
void main() {
  Future<void> pumpMainTab(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(buildTestApp(
      home: const MainTabScreen(),
      locale: const Locale('zh'),
    ));
    // 等待 PreferencesService 异步加载完成（避免 pumpAndSettle 被
    // 容器页 WebSocket 重连 Timer 卡住）
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('底部导航栏不含容器 tab，仅 4 项（概览/资源/项目/设置）', (tester) async {
    await pumpMainTab(tester);

    // 导航栏容器（实现中加 Key 便于定位）
    final navBar = find.byKey(const Key('main_bottom_nav_bar'));
    expect(navBar, findsOneWidget);

    // 导航栏内只含 4 项
    for (final label in ['概览', '资源', '项目', '设置']) {
      expect(
        find.descendant(of: navBar, matching: find.text(label)),
        findsOneWidget,
        reason: '导航栏应包含 $label',
      );
    }
    // 不再有"容器"项
    expect(
      find.descendant(of: navBar, matching: find.text('容器')),
      findsNothing,
      reason: '底部导航栏不应再有容器 tab',
    );
  });

  testWidgets('资源页第一个 tab 是容器，排在镜像页面前', (tester) async {
    await pumpMainTab(tester);
    await tapTab(tester, '资源');

    final containersLabel = find.text('容器');
    final imagesLabel = find.text('镜像');
    expect(containersLabel, findsOneWidget);
    expect(imagesLabel, findsOneWidget);

    // 容器 tab 在镜像 tab 左侧（排在前面）
    final containersX = tester.getTopLeft(containersLabel).dx;
    final imagesX = tester.getTopLeft(imagesLabel).dx;
    expect(containersX, lessThan(imagesX),
        reason: '容器 tab 应排在镜像页面前');
  });

  testWidgets('资源页默认激活容器 tab，显示容器列表页面', (tester) async {
    await pumpMainTab(tester);
    await tapTab(tester, '资源');

    expect(find.byType(HomeScreen), findsOneWidget,
        reason: '资源页默认 tab 应显示容器页面');
  });

  testWidgets('容器 tab 显示运行容器 FAB，镜像 tab 显示拉取镜像 FAB', (tester) async {
    await pumpMainTab(tester);
    await tapTab(tester, '资源');

    // 容器 tab（默认激活）→ fab_run_container
    FloatingActionButton fab() {
      return tester.widget<FloatingActionButton>(
          find.byType(FloatingActionButton));
    }

    expect(fab().heroTag, 'fab_run_container');
    expect(find.byKey(const Key('fab_pull_image')), findsNothing);

    // 切到镜像 tab → fab_pull_image
    await tapTab(tester, '镜像');
    expect(fab().heroTag, 'fab_pull_image');
    expect(find.byKey(const Key('fab_run_container')), findsNothing);
  });

  testWidgets('布局切换按钮仅资源页容器 tab 激活时显示', (tester) async {
    await pumpMainTab(tester);

    // 概览页不显示布局切换
    expect(find.byIcon(RemixIcon.listUnordered), findsNothing);

    // 资源页 + 容器 tab（默认激活）→ 显示
    await tapTab(tester, '资源');
    expect(find.byIcon(RemixIcon.listUnordered), findsOneWidget);

    // 切到镜像 tab → 隐藏
    await tapTab(tester, '镜像');
    expect(find.byIcon(RemixIcon.listUnordered), findsNothing);
  });
}
