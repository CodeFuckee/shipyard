import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_portainer_flutter_module/services/docker_service.dart';
import 'package:mobile_portainer_flutter_module/utils/container_upgrade.dart';

import 'test_utils.dart';

/// 测试用假服务：不发起真实 HTTP，可控地返回检查/升级结果。
class _FakeUpgradeService extends DockerService {
  _FakeUpgradeService({
    this.checkResult,
    this.checkError,
    this.upgradeResult,
    this.upgradeError,
  }) : super(baseUrl: 'http://fake-host');

  Map<String, dynamic>? checkResult;
  Object? checkError;
  Map<String, dynamic>? upgradeResult;
  Object? upgradeError;
  int upgradeCalls = 0;

  @override
  Future<Map<String, dynamic>> checkContainerUpdate(String id) async {
    if (checkError != null) throw checkError!;
    return checkResult ?? {'status': 'up_to_date'};
  }

  @override
  Future<Map<String, dynamic>> upgradeContainer(String id) async {
    upgradeCalls++;
    if (upgradeError != null) throw upgradeError!;
    return upgradeResult ?? {'status': 'upgraded', 'id': 'new-id', 'name': 'my-nginx'};
  }
}

/// 渲染一个按钮，点击后触发 handleContainerUpgrade 流程。
/// 指定中文 locale，确保断言的中文文案匹配。
Future<void> _pumpHarness(WidgetTester tester, DockerService service) async {
  await tester.pumpWidget(buildTestApp(
    locale: const Locale('zh'),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () =>
                handleContainerUpgrade(context, service, 'c1', 'my-nginx'),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// 多帧推进，覆盖对话框 pop/push 动画（loading 有无限动画不能用 pumpAndSettle）
Future<void> _settlePump(WidgetTester tester, {int times = 6}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _tapGo(WidgetTester tester) async {
  await tester.tap(find.text('go'));
  await _settlePump(tester); // loading 弹出 → 异步检查完成 → loading 关闭 → 结果框弹出
}

/// 点击"确认"按钮并等待升级流程完成
Future<void> _tapConfirm(WidgetTester tester) async {
  await tester.tap(find.text('确认'));
  await _settlePump(tester); // 确认框关闭 → 升级 loading → 升级完成 → 提示
}

void main() {
  tearDown(() {
    DockerService.debugHttpClient = null;
  });

  // ---------- 服务层：请求行为 ----------

  group('DockerService.checkContainerUpdate', () {
    test('发送 POST 到 check-update 并解析结果', () async {
      DockerService.debugHttpClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/containers/c1/check-update');
        expect(request.headers['x-api-key'], 'test-key');
        return http.Response(
          json.encode({
            'status': 'update_available',
            'current_image': 'nginx:1.25',
            'current_digest': 'sha256:old',
            'latest_digest': 'sha256:new',
          }),
          200,
        );
      });
      final service =
          DockerService(baseUrl: 'http://localhost:2375', apiKey: 'test-key');
      final result = await service.checkContainerUpdate('c1');
      expect(result['status'], 'update_available');
      expect(result['current_image'], 'nginx:1.25');
    });

    test('后端错误（500）时抛出异常并带出错误信息', () async {
      DockerService.debugHttpClient = MockClient(
        (request) async => http.Response('{"detail":"pull failed"}', 500),
      );
      final service = DockerService(baseUrl: 'http://localhost:2375');
      await expectLater(service.checkContainerUpdate('c1'), throwsA(isA<Exception>()));
    });
  });

  group('DockerService.upgradeContainer', () {
    test('发送 POST 到 upgrade 并解析结果', () async {
      DockerService.debugHttpClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/containers/c1/upgrade');
        return http.Response(
          json.encode({'status': 'upgraded', 'id': 'new-id', 'name': 'my-nginx'}),
          200,
        );
      });
      final service = DockerService(baseUrl: 'http://localhost:2375');
      final result = await service.upgradeContainer('c1');
      expect(result['status'], 'upgraded');
      expect(result['name'], 'my-nginx');
    });

    test('已是最新（200 up_to_date）时正常返回', () async {
      DockerService.debugHttpClient = MockClient(
        (request) async =>
            http.Response(json.encode({'status': 'up_to_date'}), 200),
      );
      final service = DockerService(baseUrl: 'http://localhost:2375');
      final result = await service.upgradeContainer('c1');
      expect(result['status'], 'up_to_date');
    });
  });

  // ---------- 升级流程对话框 ----------

  group('handleContainerUpgrade', () {
    testWidgets('检查到有更新时弹出确认框，确认后调用升级', (tester) async {
      final service = _FakeUpgradeService(
        checkResult: {
          'status': 'update_available',
          'current_image': 'nginx:1.25',
          'current_digest': 'sha256:old-digest-111',
          'latest_digest': 'sha256:new-digest-222',
        },
      );
      await _pumpHarness(tester, service);
      await _tapGo(tester);

      // 出现升级确认框，展示当前/最新版本信息（digest 截断显示前 16 字符）
      expect(find.text('确认升级'), findsOneWidget);
      expect(find.textContaining('当前版本: nginx:1.25'), findsOneWidget);
      expect(find.textContaining('sha256:new-dig'), findsOneWidget);

      // 点击确认 → 调用升级
      await _tapConfirm(tester);
      expect(service.upgradeCalls, 1);
    });

    testWidgets('确认框点击取消时不调用升级', (tester) async {
      final service = _FakeUpgradeService(
        checkResult: {'status': 'update_available'},
      );
      await _pumpHarness(tester, service);
      await _tapGo(tester);

      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(service.upgradeCalls, 0);
    });

    testWidgets('已是最新版本时提示且不调用升级', (tester) async {
      final service = _FakeUpgradeService(
        checkResult: {'status': 'up_to_date'},
      );
      await _pumpHarness(tester, service);
      await _tapGo(tester);

      expect(find.textContaining('已是最新版本'), findsWidgets);
      expect(find.text('确认'), findsOneWidget);
      await tester.tap(find.text('确认'));
      await tester.pump();
      expect(service.upgradeCalls, 0);
    });

    testWidgets('无法对比 digest（unknown）时仍可确认升级', (tester) async {
      final service = _FakeUpgradeService(
        checkResult: {'status': 'unknown'},
      );
      await _pumpHarness(tester, service);
      await _tapGo(tester);

      expect(find.text('确认升级'), findsOneWidget);
      expect(find.textContaining('无法对比镜像摘要'), findsOneWidget);

      await _tapConfirm(tester);
      expect(service.upgradeCalls, 1);
    });

    testWidgets('检查更新失败时提示失败且不弹确认框', (tester) async {
      final service = _FakeUpgradeService(checkError: Exception('network down'));
      await _pumpHarness(tester, service);
      await _tapGo(tester);

      expect(find.text('确认升级'), findsNothing);
      expect(service.upgradeCalls, 0);
    });

    testWidgets('升级失败时提示失败信息', (tester) async {
      final service = _FakeUpgradeService(
        checkResult: {'status': 'update_available'},
        upgradeError: Exception('port conflict'),
      );
      await _pumpHarness(tester, service);
      await _tapGo(tester);

      await _tapConfirm(tester);
      expect(service.upgradeCalls, 1);
      expect(find.textContaining('容器升级失败'), findsOneWidget);
    });
  });
}
