import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_portainer_flutter_module/services/docker_service.dart';

/// 复现 issue #35：shipyardx 通过 frpc 隧道访问后端时，重启 frpc 容器
/// 会导致隧道短暂中断，客户端收到 frps 的 404 页面（HTML）或网络错误，
/// 前端把这些误报为"重启失败"，但实际重启已成功。
///
/// 期望行为：restart / start 这类"隧道敏感操作"在收到隧道层 404/网络错误后，
/// 等待 API 恢复并确认容器状态，不再误报失败。
void main() {
  /// 模拟 frps 在隧道断开时返回的 404 页面（HTML，非后端 JSON）
  const frps404Body = '''
<html><head><title>404 Not Found</title></head>
<body><h1>404 Not Found</h1></body></html>
''';

  /// 后端 FastAPI 的 404 响应（JSON 对象，带 detail 字段）
  String backendJson404(String id) =>
      json.encode({'detail': 'Container $id not found'});

  tearDown(() {
    DockerService.debugHttpClient = null;
    DockerService.tunnelRecoveryTimeout = const Duration(seconds: 60);
    DockerService.tunnelRecoveryPollInterval = const Duration(seconds: 3);
  });

  DockerService buildService() =>
      DockerService(baseUrl: 'http://fake-host', apiKey: 'test-key');

  /// 构造 MockClient：POST restart 返回 404 HTML，随后 summary 探测前
  /// [summaryFails] 次仍失败（模拟 frpc 尚未恢复），恢复后容器存在。
  MockClient buildTunnelInterruptionClient({int summaryFails = 2}) {
    var summaryCalls = 0;
    return MockClient((request) async {
      if (request.method == 'POST' &&
          request.url.path.endsWith('/containers/frpc/restart')) {
        // 隧道中断瞬间：frps 返回 404 HTML 页面
        return http.Response(frps404Body, 404);
      }
      if (request.url.path.endsWith('/containers/summary')) {
        summaryCalls++;
        if (summaryCalls <= summaryFails) {
          // frpc 尚未恢复，连接被重置
          throw http.ClientException('Connection reset by peer');
        }
        return http.Response(
          json.encode([
            {'id': 'frpc', 'name': 'frpc', 'status': 'running'},
          ]),
          200,
        );
      }
      if (request.url.path.endsWith('/containers/frpc') &&
          !request.url.path.contains('/containers/frpc/')) {
        return http.Response(
          json.encode({'id': 'frpc', 'name': 'frpc', 'status': 'running'}),
          200,
        );
      }
      return http.Response('{"detail": "not found"}', 404);
    });
  }

  test('restart 收到隧道层 404 页面时，等待 API 恢复后确认成功，不抛异常', () async {
    DockerService.debugHttpClient = buildTunnelInterruptionClient();
    DockerService.tunnelRecoveryTimeout = const Duration(seconds: 5);
    DockerService.tunnelRecoveryPollInterval =
        const Duration(milliseconds: 10);

    final service = buildService();
    // 修复前：此处会抛异常（404 被直接当作操作失败）
    await service.restartContainer('frpc');
  });

  test('restart 抛出网络异常（连接重置）时，同样等待恢复并确认成功', () async {
    var postCalls = 0;
    DockerService.debugHttpClient = MockClient((request) async {
      if (request.method == 'POST' &&
          request.url.path.endsWith('/containers/frpc/restart')) {
        postCalls++;
        // 隧道中断的另一表现形式：连接被重置
        throw http.ClientException('Connection reset by peer');
      }
      if (request.url.path.endsWith('/containers/summary')) {
        return http.Response('[]', 200);
      }
      if (request.url.path == '/containers/frpc') {
        return http.Response(
          json.encode({'id': 'frpc', 'name': 'frpc', 'status': 'running'}),
          200,
        );
      }
      return http.Response('{"detail": "not found"}', 404);
    });
    DockerService.tunnelRecoveryTimeout = const Duration(seconds: 5);
    DockerService.tunnelRecoveryPollInterval =
        const Duration(milliseconds: 10);

    final service = buildService();
    await service.restartContainer('frpc');
    expect(postCalls, 1);
  });

  test('start 操作同样支持隧道恢复确认', () async {
    DockerService.debugHttpClient = MockClient((request) async {
      if (request.method == 'POST' &&
          request.url.path.endsWith('/containers/frpc/start')) {
        return http.Response(frps404Body, 404);
      }
      if (request.url.path.endsWith('/containers/summary')) {
        return http.Response('[]', 200);
      }
      if (request.url.path == '/containers/frpc') {
        return http.Response(
          json.encode({'id': 'frpc', 'name': 'frpc', 'status': 'running'}),
          200,
        );
      }
      return http.Response('{"detail": "not found"}', 404);
    });
    DockerService.tunnelRecoveryTimeout = const Duration(seconds: 5);
    DockerService.tunnelRecoveryPollInterval =
        const Duration(milliseconds: 10);

    final service = buildService();
    await service.startContainer('frpc');
  });

  test('后端 JSON 404（容器不存在）时立即报错，不进入恢复等待', () async {
    var summaryCalls = 0;
    DockerService.debugHttpClient = MockClient((request) async {
      if (request.method == 'POST') {
        return http.Response(backendJson404('frpc'), 404,
            headers: {'content-type': 'application/json'});
      }
      if (request.url.path.endsWith('/containers/summary')) {
        summaryCalls++;
        return http.Response('[]', 200);
      }
      return http.Response('{}', 200);
    });

    final service = buildService();
    await expectLater(service.restartContainer('frpc'), throwsException);
    expect(summaryCalls, 0, reason: '真实后端 404 不应触发恢复轮询');
  });

  test('API 长时间未恢复时，抛出明确的超时异常而非原始 404', () async {
    DockerService.debugHttpClient = MockClient((request) async {
      if (request.method == 'POST') {
        return http.Response(frps404Body, 404);
      }
      // 所有探测请求持续失败：frpc 一直未恢复
      throw http.ClientException('Connection reset by peer');
    });
    DockerService.tunnelRecoveryTimeout =
        const Duration(milliseconds: 300);
    DockerService.tunnelRecoveryPollInterval =
        const Duration(milliseconds: 10);

    final service = buildService();
    await expectLater(
      service.restartContainer('frpc'),
      throwsA(predicate((e) =>
          e.toString().contains('API') && e.toString().contains('恢复'))),
    );
  });

  test('API 恢复后目标容器不存在时，最终抛出异常', () async {
    DockerService.debugHttpClient = MockClient((request) async {
      if (request.method == 'POST') {
        return http.Response(frps404Body, 404);
      }
      if (request.url.path.endsWith('/containers/summary')) {
        return http.Response('[]', 200); // API 已恢复
      }
      // 但目标容器查询持续 404：视为未确认，直至超时
      return http.Response(backendJson404('frpc'), 404);
    });
    DockerService.tunnelRecoveryTimeout =
        const Duration(milliseconds: 300);
    DockerService.tunnelRecoveryPollInterval =
        const Duration(milliseconds: 10);

    final service = buildService();
    await expectLater(service.restartContainer('frpc'), throwsException);
  });

  test('非隧道敏感操作（stop）收到 404 时保持原行为直接报错', () async {
    DockerService.debugHttpClient = MockClient(
        (request) async => http.Response(frps404Body, 404));

    final service = buildService();
    await expectLater(service.stopContainer('frpc'), throwsException);
  });
}
