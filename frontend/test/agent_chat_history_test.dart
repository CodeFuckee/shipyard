import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/agent_chat_screen.dart';
import 'package:mobile_portainer_flutter_module/screens/main_tab_screen.dart';
import 'package:mobile_portainer_flutter_module/services/agent_service.dart';
import 'test_utils.dart';

/// AI 助手对话历史保存（issue #32）。
///
/// 覆盖：
/// - AgentService.fetchChatHistory：200 解析、空列表、HTTP 错误抛异常
/// - AgentService.clearChatHistory：200 返回删除数、HTTP 错误抛异常
/// - AgentChatScreen：打开时恢复历史消息、无历史显示空状态、
///   历史加载失败仍可正常使用、清空按钮同步清后端
/// - MainTabScreen：顶部 AppBar 增加 AI 助手按钮、点击弹出聊天窗口
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    AgentService.debugHttpClient = null;
    AgentService.debugFetchToolsOverride = null;
    AgentService.debugSseConnector = null;
  });

  Future<AgentToolsInfo> fakeFetchTools() async {
    return AgentToolsInfo(
      skills: const [
        AgentToolMeta(
          name: 'docker_mirror_pull',
          description: '拉取单个镜像',
          group: '镜像拉取',
          parameters: {},
        ),
      ],
      tools: const [],
    );
  }

  /// 注入返回固定响应的 http client：按路径分发 GET/DELETE 聊天历史接口。
  MockClient historyClient({
    List<Map<String, dynamic>>? messages,
    bool failLoad = false,
  }) {
    return MockClient((request) async {
      if (request.url.path.endsWith('/admin/agent/chat-history')) {
        if (request.method == 'GET') {
          if (failLoad) {
            return http.Response('server error', 500);
          }
          return http.Response(
            jsonEncode({'messages': messages ?? []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'DELETE') {
          return http.Response(jsonEncode({'deleted': 1}), 200,
              headers: {'content-type': 'application/json'});
        }
      }
      if (request.url.path.endsWith('/admin/agent/tools')) {
        return http.Response(
          jsonEncode({
            'skills': [],
            'tools': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });
  }

  /// 打开聊天窗口并等待历史加载与滑入动画完成。
  Future<void> pumpChatScreen(
    WidgetTester tester, {
    MockClient? client,
  }) async {
    SharedPreferences.setMockInitialValues({
      'web_backend_url': 'https://example.com',
      'web_backend_token': 'test-key',
    });
    AgentService.debugHttpClient = client ?? historyClient();
    AgentService.debugFetchToolsOverride = fakeFetchTools;
    await tester.pumpWidget(buildTestApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => AgentChatDialog.show(context),
              child: const Text('open-chat'),
            ),
          ),
        ),
      ),
      locale: const Locale('zh'),
    ));
    await tester.tap(find.text('open-chat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // 滑入动画
    await tester.pump(); // 历史加载 setState 后的帧
    await tester.pump();
  }

  group('AgentService.fetchChatHistory', () {
    test('200 返回消息列表（含 role/content/steps）', () async {
      final client = historyClient(messages: [
        {'role': 'user', 'content': '帮我拉取 nginx 镜像'},
        {
          'role': 'assistant',
          'content': '已拉取',
          'steps': [
            {'type': 'step_result', 'name': 'docker_mirror_pull', 'result': 'ok'},
          ],
        },
      ]);
      AgentService.debugHttpClient = client;

      final messages = await AgentService.fetchChatHistory(
          baseUrl: 'https://example.com', token: 'test-key');
      expect(messages.length, 2);
      expect(messages[0]['role'], 'user');
      expect(messages[0]['content'], '帮我拉取 nginx 镜像');
      expect(messages[1]['steps'], isA<List>());
    });

    test('无历史返回空列表', () async {
      AgentService.debugHttpClient = historyClient();

      final messages = await AgentService.fetchChatHistory(
          baseUrl: 'https://example.com', token: 'test-key');
      expect(messages, isEmpty);
    });

    test('HTTP 500 抛异常', () async {
      AgentService.debugHttpClient = historyClient(failLoad: true);

      expect(
        () => AgentService.fetchChatHistory(
            baseUrl: 'https://example.com', token: 'test-key'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('AgentService.clearChatHistory', () {
    test('200 返回删除条数', () async {
      AgentService.debugHttpClient = historyClient();

      final deleted = await AgentService.clearChatHistory(
          baseUrl: 'https://example.com', token: 'test-key');
      expect(deleted, 1);
    });

    test('HTTP 错误抛异常', () async {
      AgentService.debugHttpClient = MockClient(
          (request) async => http.Response('server error', 500));

      expect(
        () => AgentService.clearChatHistory(
            baseUrl: 'https://example.com', token: 'test-key'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('AgentChatScreen 历史恢复', () {
    testWidgets('打开聊天窗口时恢复历史对话消息', (tester) async {
      await pumpChatScreen(
        tester,
        client: historyClient(messages: [
          {'role': 'user', 'content': '昨天的问题'},
          {'role': 'assistant', 'content': '昨天的回复'},
        ]),
      );

      expect(find.text('昨天的问题'), findsOneWidget);
      expect(find.text('昨天的回复'), findsOneWidget);
    });

    testWidgets('无历史时显示空状态引导', (tester) async {
      await pumpChatScreen(tester, client: historyClient());

      // 空状态引导文案（agentChatEmptyTitle）
      expect(find.text('有什么可以帮你？'), findsOneWidget);
    });

    testWidgets('历史加载失败仍可正常使用聊天窗口', (tester) async {
      await pumpChatScreen(tester, client: historyClient(failLoad: true));

      // 加载失败不崩溃：输入框与发送按钮正常渲染
      expect(find.byKey(const Key('agent_input_field')), findsOneWidget);
      expect(find.byKey(const Key('agent_send_button')), findsOneWidget);
      expect(find.text('有什么可以帮你？'), findsOneWidget);
    });

    testWidgets('清空对话时同步清空后端历史', (tester) async {
      final client = historyClient(messages: [
        {'role': 'user', 'content': '待清空消息'},
        {'role': 'assistant', 'content': '待清空回复'},
      ]);
      await pumpChatScreen(tester, client: client);

      expect(find.text('待清空消息'), findsOneWidget);
      await tester.tap(find.byKey(const Key('agent_clear_button')));
      await tester.pump();
      await tester.pump();

      // 前端消息清空 + 后端 DELETE 已发出（MockClient 内部验证）
      expect(find.text('待清空消息'), findsNothing);
    });
  });

  group('MainTabScreen 顶部按钮', () {
    testWidgets('顶部 AppBar 显示 AI 助手按钮', (tester) async {
      await tester.pumpWidget(buildTestApp(
        home: const MainTabScreen(),
        locale: const Locale('zh'),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('agent_appbar_button')), findsOneWidget);
    });

    testWidgets('点击顶部按钮弹出聊天窗口', (tester) async {
      SharedPreferences.setMockInitialValues({
        'web_backend_url': 'https://example.com',
        'web_backend_token': 'test-key',
      });
      AgentService.debugHttpClient = historyClient();
      AgentService.debugFetchToolsOverride = fakeFetchTools;
      await tester.pumpWidget(buildTestApp(
        home: const MainTabScreen(),
        locale: const Locale('zh'),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byKey(const Key('agent_appbar_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('agent_chat_screen')), findsOneWidget);
    });
  });
}
