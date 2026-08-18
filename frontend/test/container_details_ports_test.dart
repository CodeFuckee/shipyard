import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_portainer_flutter_module/screens/container_details_screen.dart';
import 'package:mobile_portainer_flutter_module/services/docker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'test_utils.dart';

/// Issue #41：容器详情页（容器页面）「概览」Tab 增加「端口」区块，
/// 展示容器暴露端口（Config.ExposedPorts）与宿主机映射（NetworkSettings.Ports）；
/// 仅暴露未映射的端口显示「未映射」文案。
void main() {
  tearDown(() {
    DockerService.debugHttpClient = null;
  });

  /// 构造 docker inspect 响应。
  Map<String, dynamic> buildInspect({
    Map<String, dynamic>? exposedPorts,
    Map<String, dynamic>? publishedPorts,
    String status = 'running',
  }) {
    return {
      'Id': 'abc123def456',
      'Name': '/test-nginx',
      'Driver': 'overlay2',
      'Created': '2026-01-01T00:00:00Z',
      'Platform': 'linux',
      'RestartCount': 0,
      'State': {
        'Status': status,
        'Running': status == 'running',
        'Pid': 123,
        'ExitCode': 0,
        'StartedAt': '2026-01-01T00:00:00Z',
        'FinishedAt': '0001-01-01T00:00:00Z',
      },
      'Config': {
        'Image': 'nginx:latest',
        'Hostname': 'test-nginx',
        'ExposedPorts': exposedPorts ?? <String, dynamic>{},
      },
      'HostConfig': {
        'Runtime': 'runc',
        'Privileged': false,
        'AutoRemove': false,
        'RestartPolicy': {'Name': 'no'},
      },
      'NetworkSettings': {
        'Ports': publishedPorts ?? <String, dynamic>{},
      },
    };
  }

  MockClient buildClient(Map<String, dynamic> inspect) {
    return MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path == '/containers/test-nginx') {
        return http.Response(json.encode(inspect), 200);
      }
      return http.Response('{"detail": "not found"}', 404);
    });
  }

  /// 概览 Tab 为 ListView 懒加载，滚动到底部以构建端口区块。
  Future<void> scrollOverviewToBottom(WidgetTester tester) async {
    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpDetailsScreen(WidgetTester tester, {Locale? locale}) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(buildTestApp(
      locale: locale,
      home: ContainerDetailsScreen(
        containerId: 'test-nginx',
        containerName: 'Test Nginx',
        apiUrl: 'http://fake-host',
        apiKey: 'test-key',
        ignoreSsl: true,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('概览 Tab 展示暴露端口及宿主机映射，未映射显示 Not mapped', (tester) async {
    DockerService.debugHttpClient = buildClient(buildInspect(
      exposedPorts: {'80/tcp': {}, '443/tcp': {}},
      publishedPorts: {
        '80/tcp': [
          {'HostIp': '0.0.0.0', 'HostPort': '8080'},
        ],
        '443/tcp': null,
      },
    ));

    await pumpDetailsScreen(tester);

    // 概览 Tab 为默认第一个 Tab，滚动到底部使端口区块可见
    await scrollOverviewToBottom(tester);

    expect(find.text('Ports'), findsOneWidget);
    expect(find.text('0.0.0.0:8080'), findsOneWidget);
    expect(find.text('Not mapped'), findsOneWidget);
  });

  testWidgets('未映射的暴露端口显示中文「未映射」文案', (tester) async {
    DockerService.debugHttpClient = buildClient(buildInspect(
      exposedPorts: {'22/tcp': {}},
      publishedPorts: {'22/tcp': null},
    ));

    await pumpDetailsScreen(tester, locale: const Locale('zh'));

    await scrollOverviewToBottom(tester);

    expect(find.text('端口'), findsOneWidget);
    expect(find.text('22/tcp'), findsOneWidget);
    expect(find.text('未映射'), findsOneWidget);
  });

  testWidgets('无暴露端口时不渲染端口区块', (tester) async {
    DockerService.debugHttpClient = buildClient(buildInspect());

    await pumpDetailsScreen(tester);

    expect(find.text('Ports'), findsNothing);
    expect(find.text('Not mapped'), findsNothing);
  });

  testWidgets('停止的容器 NetworkSettings.Ports 为空时仍展示暴露端口', (tester) async {
    // 停止的容器 NetworkSettings.Ports 可能为空，但 Config.ExposedPorts 仍保留
    DockerService.debugHttpClient = buildClient(buildInspect(
      exposedPorts: {'8080/tcp': {}},
      status: 'exited',
    ));

    await pumpDetailsScreen(tester);

    await scrollOverviewToBottom(tester);

    expect(find.text('Ports'), findsOneWidget);
    expect(find.text('8080/tcp'), findsOneWidget);
    expect(find.text('Not mapped'), findsOneWidget);
  });
}
