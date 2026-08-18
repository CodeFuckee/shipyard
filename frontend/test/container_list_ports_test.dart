import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/home_screen.dart';
import 'package:mobile_portainer_flutter_module/screens/stack_containers_screen.dart';
import 'package:mobile_portainer_flutter_module/services/docker_service.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'test_utils.dart';

/// issue #48：容器页面（列表）直接显示容器暴露的端口，
/// 不需要点击进入详情页即可看到端口。
///
/// 覆盖场景：
/// - 首页容器 tab 的 grid（卡片）模式已显示端口（基线）
/// - 首页容器 tab 的 list（紧凑）模式补上端口显示
/// - 栈容器页面卡片模式已显示端口（基线）
/// - 栈容器页面紧凑模式补上端口显示
/// - 无端口容器不显示端口行（边界）
void main() {
  tearDown(() {
    DockerService.debugHttpClient = null;
  });

  Map<String, dynamic> buildContainer({
    required String id,
    required String name,
    String status = 'running',
    String ports = '',
    String image = 'nginx:latest',
  }) {
    return {
      'id': id,
      'name': name,
      'status': status,
      'stack': '',
      'image': image,
      'ports': ports,
      'is_self': false,
    };
  }

  /// 渲染首页容器 tab（HomeScreen）。
  Future<void> pumpHomeScreen(
    WidgetTester tester, {
    required String layoutMode,
    required List<Map<String, dynamic>> containers,
  }) async {
    SharedPreferences.setMockInitialValues({
      'docker_api_url': 'http://127.0.0.1:9000',
      'docker_api_key': '',
    });
    DockerService.debugHttpClient = MockClient((request) async {
      if (request.url.path == '/containers/summary') {
        return http.Response(jsonEncode(containers), 200);
      }
      if (request.url.path == '/stacks') {
        return http.Response(jsonEncode([]), 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(buildTestApp(
      home: Scaffold(body: HomeScreen(layoutMode: layoutMode)),
      locale: const Locale('zh'),
    ));
    // 固定帧推进（容器页 WebSocket 重连 Timer 会卡住 pumpAndSettle），
    // 多帧推进等待异步加载（prefs + 容器列表请求）完成
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

  }

  /// 卸载 widget 树触发 dispose，取消 WebSocket 重连 Timer。
  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  /// 渲染栈容器页面，并通过工具栏按钮切换紧凑模式。
  Future<void> pumpStackContainers(
    WidgetTester tester, {
    required List<Map<String, dynamic>> containers,
    bool compact = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      'docker_api_url': 'http://127.0.0.1:9000',
      'docker_api_key': '',
    });
    DockerService.debugHttpClient = MockClient((request) async {
      if (request.url.path == '/stacks/mystack/containers') {
        return http.Response(jsonEncode(containers), 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(buildTestApp(
      home: StackContainersScreen(stackName: 'mystack'),
      locale: const Locale('zh'),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    if (compact) {
      // 点击工具栏布局切换按钮进入紧凑模式
      await tester.tap(find.byIcon(RemixIcon.listUnordered));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }

  }

  group('首页容器 tab 端口显示（issue #48）', () {
    testWidgets('list 紧凑模式显示容器暴露端口', (tester) async {
      await pumpHomeScreen(
        tester,
        layoutMode: 'list',
        containers: [
          buildContainer(
            id: 'c1',
            name: 'web',
            ports: '8080->80/tcp, 8443->443/tcp',
          ),
        ],
      );

      // 容器名已渲染
      expect(find.text('web'), findsOneWidget);
      // 端口内容直接可见（无需进入详情页）
      expect(find.textContaining('8080->80/tcp, 8443->443/tcp'), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('list 紧凑模式无端口容器不显示端口行', (tester) async {
      await pumpHomeScreen(
        tester,
        layoutMode: 'list',
        containers: [buildContainer(id: 'c1', name: 'web', ports: '')],
      );

      expect(find.text('web'), findsOneWidget);
      expect(find.textContaining('端口'), findsNothing);

      await disposeTree(tester);
    });

    testWidgets('grid 卡片模式显示容器暴露端口（基线）', (tester) async {
      await pumpHomeScreen(
        tester,
        layoutMode: 'grid',
        containers: [
          buildContainer(
            id: 'c1',
            name: 'web',
            ports: '8080->80/tcp',
          ),
        ],
      );

      expect(find.text('web'), findsOneWidget);
      expect(find.text('8080->80/tcp'), findsOneWidget);

      await disposeTree(tester);
    });
  });

  group('栈容器页面端口显示（issue #48）', () {
    testWidgets('紧凑模式显示容器暴露端口', (tester) async {
      await pumpStackContainers(
        tester,
        compact: true,
        containers: [
          buildContainer(
            id: 'c1',
            name: 'db',
            ports: '5432->5432/tcp',
          ),
        ],
      );

      expect(find.text('db'), findsOneWidget);
      expect(find.textContaining('5432->5432/tcp'), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('卡片模式显示容器暴露端口（基线）', (tester) async {
      await pumpStackContainers(
        tester,
        containers: [
          buildContainer(
            id: 'c1',
            name: 'db',
            ports: '5432->5432/tcp',
          ),
        ],
      );

      expect(find.text('db'), findsOneWidget);
      expect(find.text('5432->5432/tcp'), findsOneWidget);

      await disposeTree(tester);
    });
  });
}
