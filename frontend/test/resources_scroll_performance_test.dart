import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/main_tab_screen.dart';
import 'package:mobile_portainer_flutter_module/services/docker_service.dart';
import 'test_utils.dart';

/// issue #30：资源页面列表 item 多时滚动卡顿。
///
/// 根因 1（主因）：底部悬浮导航栏使用 BackdropFilter（sigma 20 高斯模糊）
/// 覆盖在滚动列表上方。滚动时列表内容每帧变化，导航栏背后的模糊背景
/// 每帧重新录制 + 重算模糊，item 越多绘制量越大，叠加成本导致滚动卡顿。
/// 修复：滚动进行中暂停背景模糊（BackdropFilter.enabled = false），
/// 滚动停止后恢复。
void main() {
  tearDown(() {
    DockerService.debugHttpClient = null;
  });

  testWidgets('资源页列表滚动时底部导航栏应暂停背景模糊', (tester) async {
    tester.view.physicalSize = const Size(560, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({
      'docker_api_url': 'http://127.0.0.1:9000',
      'docker_api_key': '',
    });

    // mock 100 个容器：item 多时的典型场景
    DockerService.debugHttpClient = MockClient((request) async {
      if (request.url.path == '/containers/summary') {
        final containers = List.generate(100, (i) {
          return {
            'id': 'container-$i',
            'name': 'container-$i',
            'status': 'running',
            'image': 'nginx:latest',
            'ports': '',
            'is_self': false,
          };
        });
        return http.Response(jsonEncode(containers), 200);
      }
      if (request.url.path == '/stacks') {
        return http.Response(jsonEncode([]), 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(buildTestApp(
      home: const MainTabScreen(),
      locale: const Locale('zh'),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // 切到资源页（容器 tab 默认激活）
    await tester.tap(find.text('资源'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 50));

    // 100 个容器的列表已渲染
    expect(find.text('container-0'), findsWidgets,
        reason: '容器列表应已加载渲染');

    // 精确定位导航栏内的 BackdropFilter（toast 等其他 BackdropFilter 不干扰）
    BackdropFilter backdropFilter() => tester.widget<BackdropFilter>(
          find.descendant(
            of: find.byKey(const Key('main_bottom_nav_bar')),
            matching: find.byType(BackdropFilter),
          ),
        );

    // 静止时导航栏背景模糊开启
    expect(backdropFilter().enabled, isTrue,
        reason: '列表静止时导航栏模糊应开启');

    // 按住列表拖动 → 滚动进行中
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(ListView)));
    await gesture.moveBy(const Offset(0, -200));
    await tester.pump(const Duration(milliseconds: 16));

    // 滚动中应暂停模糊（当前实现 enabled 恒 true → 此处失败，复现卡顿根因）
    expect(backdropFilter().enabled, isFalse,
        reason: '滚动进行中应暂停导航栏背景模糊，避免每帧重算 blur');

    // 手指抬起 → 滚动结束 → 恢复模糊
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 600));
    expect(backdropFilter().enabled, isTrue,
        reason: '滚动停止后应恢复导航栏背景模糊');
  });
}
