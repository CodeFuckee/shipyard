import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/agent_debug_log_detail_screen.dart';
import 'package:mobile_portainer_flutter_module/screens/agent_debug_logs_screen.dart';
import 'package:mobile_portainer_flutter_module/services/agent_service.dart';

import 'test_utils.dart';

/// Fake 后端：内存维护记录列表，响应列表/详情/清空请求。
class FakeDebugLogBackend {
  final List<Map<String, dynamic>> logs;
  int clearCalls = 0;

  FakeDebugLogBackend(this.logs);

  MockClient get client => MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'DELETE' && path.endsWith('/debug-logs')) {
          clearCalls++;
          final deleted = logs.length;
          logs.clear();
          return http.Response.bytes(
              utf8.encode(jsonEncode({'deleted': deleted})), 200);
        }
        if (path.endsWith('/debug-logs')) {
          return http.Response.bytes(
              utf8.encode(jsonEncode({'logs': logs})), 200);
        }
        // 详情：/admin/agent/debug-logs/{id}
        final id = path.split('/').last;
        final match = logs.where((l) => l['id'] == id).toList();
        if (match.isEmpty) {
          return http.Response('{"detail":"not found"}', 404);
        }
        return http.Response.bytes(
            utf8.encode(jsonEncode(match.first)), 200);
      });
}

/// AI 调试日志功能测试（issue #24）：
/// 模型解析、服务层（列表/详情/清空）、列表页与详情页渲染。
///
/// 通过 AgentService.debugHttpClient 注入 MockClient，Fake 后端内存维护
/// 记录列表，覆盖正常路径与边界（空列表、错误态、清空确认、错误详情）。
void main() {
  tearDown(() {
    AgentService.debugHttpClient = null;
  });

  Map<String, dynamic> summaryJson({
    String id = 'log-1',
    String createdAt = '2026-08-13T10:00:00',
    String requestText = '帮我拉取 nginx 镜像',
    String? llmSource = 'hermes',
    String? llmName = 'Hermes',
    String? llmModel = 'hermes-chat',
    String status = 'success',
    int durationMs = 1234,
  }) {
    return {
      'id': id,
      'created_at': createdAt,
      'request_text': requestText,
      'llm_source': llmSource,
      'llm_name': llmName,
      'llm_model': llmModel,
      'status': status,
      'duration_ms': durationMs,
    };
  }

  Map<String, dynamic> detailJson({
    String status = 'success',
    String errorMessage = '',
    List<Map<String, dynamic>>? events,
    List<Map<String, dynamic>>? messages,
    String reply = '好的，已拉取 nginx 镜像',
  }) {
    return {
      ...summaryJson(status: status),
      'tools_names': ['docker_mirror_pull'],
      'error_message': errorMessage,
      'messages': messages ??
          [
            {'role': 'user', 'content': '帮我拉取 nginx 镜像'},
          ],
      'events': events ??
          [
            {
              'type': 'step',
              'name': 'docker_mirror_pull',
              'arguments': {'image': 'nginx'},
            },
            {
              'type': 'step_result',
              'name': 'docker_mirror_pull',
              'result': '拉取成功',
            },
          ],
      'reply': reply,
    };
  }

  // --- 模型解析 ---

  group('AgentDebugLogSummary.fromJson', () {
    test('完整字段解析', () {
      final s = AgentDebugLogSummary.fromJson(summaryJson());
      expect(s.id, 'log-1');
      expect(s.createdAt, '2026-08-13T10:00:00');
      expect(s.requestText, '帮我拉取 nginx 镜像');
      expect(s.llmSource, 'hermes');
      expect(s.llmName, 'Hermes');
      expect(s.llmModel, 'hermes-chat');
      expect(s.status, 'success');
      expect(s.isSuccess, isTrue);
      expect(s.durationMs, 1234);
    });

    test('缺省字段回退安全值（边界：空 JSON）', () {
      final s = AgentDebugLogSummary.fromJson(const {});
      expect(s.id, '');
      expect(s.requestText, '');
      expect(s.llmSource, isNull);
      expect(s.status, 'success');
      expect(s.isSuccess, isTrue);
      expect(s.durationMs, 0);
    });

    test('error 状态解析', () {
      final s = AgentDebugLogSummary.fromJson(
          summaryJson(status: 'error', llmSource: null));
      expect(s.isSuccess, isFalse);
      expect(s.llmSource, isNull);
    });
  });

  group('AgentDebugLogDetail.fromJson', () {
    test('完整字段解析', () {
      final d = AgentDebugLogDetail.fromJson(detailJson());
      expect(d.summary.id, 'log-1');
      expect(d.toolsNames, ['docker_mirror_pull']);
      expect(d.errorMessage, '');
      expect(d.messages, hasLength(1));
      expect(d.messages.first['role'], 'user');
      expect(d.events, hasLength(2));
      expect(d.events.first['type'], 'step');
      expect(d.reply, '好的，已拉取 nginx 镜像');
    });

    test('边界：字段缺失返回空集合', () {
      final d = AgentDebugLogDetail.fromJson(summaryJson());
      expect(d.toolsNames, isEmpty);
      expect(d.messages, isEmpty);
      expect(d.events, isEmpty);
      expect(d.reply, '');
      expect(d.errorMessage, '');
    });
  });

  // --- 服务层 ---

  group('fetchDebugLogs', () {
    test('200 解析日志列表', () async {
      AgentService.debugHttpClient = MockClient((request) async {
        expect(request.url.toString(),
            'https://example.com/admin/agent/debug-logs');
        expect(request.headers['X-API-Key'], 'test-key');
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'logs': [summaryJson(), summaryJson(id: 'log-2')]
            })),
            200);
      });

      final logs = await AgentService.fetchDebugLogs(
          baseUrl: 'https://example.com', token: 'test-key');
      expect(logs, hasLength(2));
      expect(logs.first.id, 'log-1');
      expect(logs.last.id, 'log-2');
    });

    test('空列表（边界）', () async {
      AgentService.debugHttpClient =
          MockClient((request) async => http.Response('{"logs": []}', 200));
      final logs = await AgentService.fetchDebugLogs(
          baseUrl: 'https://example.com', token: 'test-key');
      expect(logs, isEmpty);
    });

    test('500 抛出异常', () async {
      AgentService.debugHttpClient =
          MockClient((request) async => http.Response('Internal Error', 500));
      await expectLater(
        AgentService.fetchDebugLogs(
            baseUrl: 'https://example.com', token: 'test-key'),
        throwsException,
      );
    });

    test('响应体非对象（边界）', () async {
      AgentService.debugHttpClient =
          MockClient((request) async => http.Response('[1,2,3]', 200));
      final logs = await AgentService.fetchDebugLogs(
          baseUrl: 'https://example.com', token: 'test-key');
      expect(logs, isEmpty);
    });
  });

  group('fetchDebugLogDetail', () {
    test('200 解析详情', () async {
      AgentService.debugHttpClient = MockClient((request) async {
        expect(request.url.toString(),
            'https://example.com/admin/agent/debug-logs/log-1');
        return http.Response.bytes(
            utf8.encode(jsonEncode(detailJson())), 200);
      });

      final d = await AgentService.fetchDebugLogDetail(
          baseUrl: 'https://example.com', token: 'test-key', id: 'log-1');
      expect(d.summary.id, 'log-1');
      expect(d.events, hasLength(2));
    });

    test('404 抛出异常', () async {
      AgentService.debugHttpClient = MockClient(
          (request) async => http.Response('{"detail":"not found"}', 404));
      await expectLater(
        AgentService.fetchDebugLogDetail(
            baseUrl: 'https://example.com', token: 'test-key', id: 'nope'),
        throwsException,
      );
    });
  });

  group('clearDebugLogs', () {
    test('200 返回删除条数', () async {
      AgentService.debugHttpClient = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.toString(),
            'https://example.com/admin/agent/debug-logs');
        return http.Response('{"deleted": 3}', 200);
      });

      final deleted = await AgentService.clearDebugLogs(
          baseUrl: 'https://example.com', token: 'test-key');
      expect(deleted, 3);
    });

    test('500 抛出异常', () async {
      AgentService.debugHttpClient =
          MockClient((request) async => http.Response('oops', 500));
      await expectLater(
        AgentService.clearDebugLogs(
            baseUrl: 'https://example.com', token: 'test-key'),
        throwsException,
      );
    });
  });

  // --- Widget 测试 ---

  Future<void> pumpLogsScreen(WidgetTester tester, FakeDebugLogBackend backend) async {
    SharedPreferences.setMockInitialValues({
      'docker_auth_server_url': 'https://home.chenkaidi.top:507',
      'docker_auth_token': 'token-1',
    });
    AgentService.debugHttpClient = backend.client;
    await tester.pumpWidget(buildTestApp(
      locale: const Locale('zh'),
      home: const AgentDebugLogsScreen(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('AgentDebugLogsScreen', () {
    testWidgets('显示标题与记录列表', (tester) async {
      final backend = FakeDebugLogBackend([summaryJson(), summaryJson(id: 'log-2', status: 'error')]);
      await pumpLogsScreen(tester, backend);

      expect(find.text('AI 调试日志'), findsOneWidget);
      expect(find.text('帮我拉取 nginx 镜像'), findsNWidgets(2));
      // 成功/失败状态图标
      expect(find.byIcon(RemixIcon.checkboxCircleLine), findsOneWidget);
      expect(find.byIcon(RemixIcon.closeCircleLine), findsOneWidget);
      // 副标题含 LLM 名称
      expect(find.textContaining('Hermes'), findsWidgets);
      // 耗时显示
      expect(find.text('1.2 s'), findsNWidgets(2));
    });

    testWidgets('空列表显示空态与刷新按钮', (tester) async {
      final backend = FakeDebugLogBackend([]);
      await pumpLogsScreen(tester, backend);

      expect(find.text('暂无调试记录'), findsOneWidget);
      expect(find.text('刷新'), findsOneWidget);
      // 空列表时清空按钮禁用
      final clearButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, RemixIcon.deleteBinLine),
      );
      expect(clearButton.onPressed, isNull);
    });

    testWidgets('后端返回 500 显示错误态与重试', (tester) async {
      SharedPreferences.setMockInitialValues({
        'docker_auth_server_url': 'https://home.chenkaidi.top:507',
        'docker_auth_token': 'token-1',
      });
      AgentService.debugHttpClient =
          MockClient((request) async => http.Response('boom', 500));
      await tester.pumpWidget(buildTestApp(
        locale: const Locale('zh'),
        home: const AgentDebugLogsScreen(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('加载调试日志失败'), findsOneWidget);
    });

    testWidgets('清空流程：确认对话框 → 清空 → 空态提示', (tester) async {
      final backend = FakeDebugLogBackend([summaryJson()]);
      await pumpLogsScreen(tester, backend);

      await tester.tap(find.byIcon(RemixIcon.deleteBinLine));
      await tester.pumpAndSettle();
      expect(find.text('清空调试日志？'), findsOneWidget);

      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();

      expect(backend.clearCalls, 1);
      expect(find.text('暂无调试记录'), findsOneWidget);
      expect(find.text('已清空调试日志'), findsOneWidget); // snackbar
    });

    testWidgets('清空确认取消不删除（边界）', (tester) async {
      final backend = FakeDebugLogBackend([summaryJson()]);
      await pumpLogsScreen(tester, backend);

      await tester.tap(find.byIcon(RemixIcon.deleteBinLine));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(backend.clearCalls, 0);
      expect(find.text('帮我拉取 nginx 镜像'), findsOneWidget);
    });

    testWidgets('点击记录跳转详情页', (tester) async {
      final backend = FakeDebugLogBackend([detailJson()]);
      await pumpLogsScreen(tester, backend);

      await tester.tap(find.text('帮我拉取 nginx 镜像'));
      await tester.pumpAndSettle();

      expect(find.text('调试详情'), findsOneWidget);
    });
  });

  group('AgentDebugLogDetailScreen', () {
    Future<void> pumpDetailScreen(WidgetTester tester, FakeDebugLogBackend backend) async {
      SharedPreferences.setMockInitialValues({
        'docker_auth_server_url': 'https://home.chenkaidi.top:507',
        'docker_auth_token': 'token-1',
      });
      AgentService.debugHttpClient = backend.client;
      await tester.pumpWidget(buildTestApp(
        locale: const Locale('zh'),
        home: const AgentDebugLogDetailScreen(logId: 'log-1'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('渲染概览、执行链路、对话与回复', (tester) async {
      final backend = FakeDebugLogBackend([detailJson()]);
      await pumpDetailScreen(tester, backend);

      // 概览：状态、LLM 来源、模型、工具
      expect(find.text('成功'), findsOneWidget);
      expect(find.text('Hermes'), findsOneWidget);
      expect(find.text('hermes-chat'), findsOneWidget);
      expect(find.text('docker_mirror_pull'), findsOneWidget);
      // 执行链路：工具调用 + 工具结果
      expect(find.text('执行链路'), findsOneWidget);
      expect(find.text('工具调用：docker_mirror_pull'), findsOneWidget);
      expect(find.text('工具结果：docker_mirror_pull'), findsOneWidget);
      // 对话内容与回复
      expect(find.text('对话内容'), findsOneWidget);
      expect(find.text('你'), findsOneWidget);
      expect(find.text('帮我拉取 nginx 镜像'), findsWidgets);
      expect(find.text('回复'), findsOneWidget);
      expect(find.text('好的，已拉取 nginx 镜像'), findsOneWidget);
    });

    testWidgets('失败记录显示错误信息卡（边界）', (tester) async {
      final backend = FakeDebugLogBackend([
        detailJson(
          status: 'error',
          errorMessage: 'Agent 执行异常：拉取超时',
          events: [
            {
              'type': 'step',
              'name': 'docker_mirror_pull',
              'arguments': {'image': 'nginx'},
            },
          ],
          reply: '',
        ),
      ]);
      await pumpDetailScreen(tester, backend);

      expect(find.text('失败'), findsOneWidget);
      expect(find.text('错误信息'), findsOneWidget);
      expect(find.textContaining('拉取超时'), findsOneWidget);
      // 失败前的步骤仍展示
      expect(find.text('工具调用：docker_mirror_pull'), findsOneWidget);
      // 无回复区
      expect(find.text('回复'), findsNothing);
    });

    testWidgets('非流式步骤（role 键）渲染（边界）', (tester) async {
      final backend = FakeDebugLogBackend([
        detailJson(
          events: [
            {'role': 'ai', 'content': '我来调用工具'},
            {'role': 'tool', 'content': '拉取成功'},
          ],
        ),
      ]);
      await pumpDetailScreen(tester, backend);

      expect(find.text('AI 步骤'), findsOneWidget);
      expect(find.text('工具结果'), findsOneWidget);
      expect(find.text('我来调用工具'), findsOneWidget);
      expect(find.text('拉取成功'), findsOneWidget);
    });

    testWidgets('详情加载失败显示错误态（边界）', (tester) async {
      SharedPreferences.setMockInitialValues({
        'docker_auth_server_url': 'https://home.chenkaidi.top:507',
        'docker_auth_token': 'token-1',
      });
      AgentService.debugHttpClient =
          MockClient((request) async => http.Response('boom', 500));
      await tester.pumpWidget(buildTestApp(
        locale: const Locale('zh'),
        home: const AgentDebugLogDetailScreen(logId: 'log-1'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('加载调试日志失败'), findsOneWidget);
    });
  });
}
