import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/main_tab_screen.dart';
import 'package:mobile_portainer_flutter_module/screens/home_screen.dart';
import 'test_utils.dart';

/// issue #20：概览页点击另一个服务器卡片跳转到容器页时，容器数据没有刷新。
///
/// 背景：概览页切换服务器只更新了 prefs 并切换到资源页容器 tab，但容器页
/// HomeScreen 是 IndexedStack 常驻组件，initState 只执行一次，不会重新读取
/// 新服务器的 docker_api_url，导致仍显示旧服务器的容器。
void main() {
  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('概览页点击服务器 B 卡片后，容器页应加载新服务器 B 的数据', (tester) async {
    SharedPreferences.setMockInitialValues({
      // 当前激活服务器 A
      'docker_api_url': 'http://server-a:8000',
      'docker_api_key': 'key-of-server-A',
      'docker_ignore_ssl': 'false',
      'docker_auth_server_url': 'http://server-a:8000',
      'docker_auth_token': 'key-of-server-A',
      // 服务器列表：A（当前激活）+ B
      'server_list': jsonEncode([
        {
          'name': 'Server A',
          'url': 'http://server-a:8000',
          'apiKey': 'key-of-server-A',
          'ignoreSsl': 'false',
        },
        {
          'name': 'Server B',
          'url': 'http://server-b:8000',
          'apiKey': 'key-of-server-B',
          'ignoreSsl': 'false',
        },
      ]),
    });

    await tester.pumpWidget(buildTestApp(
      home: const MainTabScreen(),
      locale: const Locale('zh'),
    ));
    // 等待概览页异步加载服务器列表
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // 概览页应显示两个服务器卡片
    expect(find.text('Server A'), findsOneWidget,
        reason: '概览页应显示服务器 A 卡片');
    expect(find.text('Server B'), findsOneWidget,
        reason: '概览页应显示服务器 B 卡片');

    // 点击服务器 B 卡片，切换到 B 并跳转容器页
    await tester.tap(find.text('Server B'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // 容器页应重新读取 prefs 中切换后的服务器地址（B），
    // 否则仍用旧服务器 A 的地址请求容器列表（issue #20 现象）
    final homeState = tester.state<HomeScreenState>(find.byType(HomeScreen));
    expect(homeState.currentApiUrl, 'http://server-b:8000',
        reason: '切换服务器后容器页应加载新服务器 B 的数据');

    // 卸载触发 dispose 取消重试/重连 Timer
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
