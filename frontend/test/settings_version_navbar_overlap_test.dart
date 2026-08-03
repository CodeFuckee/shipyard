import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mobile_portainer_flutter_module/screens/settings_screen.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'test_utils.dart';

/// 复现并验证 bug：
/// 设置页底部的版本号和构建时间被底部导航栏遮挡。
///
/// 历史根因：MainTabScreen 通过 Stack + Positioned(bottom: 0) 将
/// 高 68 的 tab 栏覆盖在页面内容之上，而设置页 ListView 的底部
/// padding 仅 32px（settings_screen.dart:726），小于 tab 栏高度，
/// 滚动到底时最后的内容被覆盖。
///
/// 修复方案（方案 B）：MainTabScreen 改用 Scaffold.bottomNavigationBar
/// 承载 tab 栏，body 自动减去导航栏高度，各页面内容天然避让。
/// 本测试模拟修复后的 MainTabScreen 布局，守护设置页版本信息
/// 不被导航栏遮挡的回归。
void main() {
  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
  });

  /// 模拟修复后的 MainTabScreen 布局：tab 栏通过
  /// Scaffold.bottomNavigationBar 承载（高度 68 与
  /// main_tab_screen.dart 的 AppTheme.bottomNavBarHeight 一致），
  /// body 自动避让。
  Future<void> pumpSettingsWithBottomNavBar(WidgetTester tester,
      {String buildTime = ''}) async {
    // 视口高度较小，预置多个 server 让设置页内容溢出屏幕、需要滚动。
    // （测试 Ahem 字体下过窄的宽度会让设置页 DropdownButton 出现
    // RenderFlex overflow 布局噪音，与本次 bug 无关，故宽度放宽。）
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({
      'docker_auth_token': 'test-token',
      'docker_auth_server_url': 'http://test-server:9000',
      'docker_api_key': 'test-api-key',
      'docker_api_url': 'http://test-server:9000/api',
      // 预置 5 个 server，让 Server 列表足够高，内容溢出屏幕
      'server_list': jsonEncode([
        for (var i = 1; i <= 5; i++)
          {
            'name': 'Server $i',
            'url': 'http://test-server-$i:9000/api',
            'apiKey': 'test-api-key-$i',
          }
      ]),
    });
    PackageInfo.setMockInitialValues(
      appName: 'Test',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'test-signature',
    );

    await tester.pumpWidget(buildTestApp(
      home: Scaffold(
        body: SettingsScreen(buildTime: buildTime),
        // 模拟 MainTabScreen 的 bottomNavigationBar tab 栏
        bottomNavigationBar: Container(
          key: const Key('bottom_nav_bar'),
          height: 68,
          color: Colors.grey,
        ),
      ),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  /// 将设置页列表滚动到底部，并返回底部导航栏的 rect。
  Future<Rect> scrollSettingsToBottom(WidgetTester tester) async {
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    // 渲染滚动后的帧，让 cacheExtent 内的内容完成布局
    await tester.pump();
    return tester.getRect(find.byKey(const Key('bottom_nav_bar')));
  }

  testWidgets('滚动到底后版本号不被底部导航栏遮挡', (tester) async {
    await pumpSettingsWithBottomNavBar(tester);

    // 先确认内容确实溢出、列表可滚动（复现的前提条件）
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0),
        reason: '设置页内容应溢出屏幕，否则无法复现遮挡场景');

    // PackageInfo mock 版本 1.0.0+1 → 徽章文本 v1.0.0+1
    final versionTextFinder = find.text('v1.0.0+1');
    expect(versionTextFinder, findsOneWidget);

    final navBarRect = await scrollSettingsToBottom(tester);
    final versionRect = tester.getRect(versionTextFinder);

    // 版本号徽章底部必须位于导航栏之上，不被遮挡
    expect(versionRect.bottom, lessThanOrEqualTo(navBarRect.top),
        reason: '版本号徽章底部(距屏幕底部 ${800 - versionRect.bottom}px) '
            '被高 ${navBarRect.height}px 的底部导航栏(top=${navBarRect.top})遮挡');
  });

  testWidgets('滚动到底后构建时间不被底部导航栏遮挡', (tester) async {
    const buildTime = '2026-08-02 15:30:45';
    await pumpSettingsWithBottomNavBar(tester, buildTime: buildTime);

    final t = AppLocalizations.of(
        tester.element(find.byType(SettingsScreen)))!;
    final buildTimeFinder = find.textContaining(t.labelBuildTime);
    expect(buildTimeFinder, findsOneWidget);

    final navBarRect = await scrollSettingsToBottom(tester);
    final buildTimeRect = tester.getRect(buildTimeFinder);

    // 构建时间文本（列表最后一行）底部必须位于导航栏之上，不被遮挡
    expect(buildTimeRect.bottom, lessThanOrEqualTo(navBarRect.top),
        reason: '构建时间底部(距屏幕底部 ${800 - buildTimeRect.bottom}px) '
            '被高 ${navBarRect.height}px 的底部导航栏(top=${navBarRect.top})遮挡');
  });
}
