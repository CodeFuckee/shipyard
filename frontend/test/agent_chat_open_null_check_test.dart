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

/// issue #37：点击右上角按钮打开 AI 聊天对话框时控制台报
/// "Null check operator used on a null value"（Web WASM 构建）。
///
/// 疑似时序：initState 的 320ms 自动聚焦（issue #34 规避引擎竞态引入）
/// 与 `_loadChatHistory` / `_loadTools` 异步 setState 引起的布局更新，
/// 在 Web 引擎上撞上输入连接建立/变换更新竞态（框架层
/// `_updateSizeAndTransform` 对 `_textInputConnection!` 做 null check）。
///
/// 本测试精确复现该时序：历史消息加载延迟到聚焦窗口内 / 聚焦刚建立后
/// 返回，逐帧推进渲染并断言全程无未捕获异常、输入框最终获得焦点。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    AgentService.debugHttpClient = null;
    AgentService.debugFetchToolsOverride = null;
    AgentService.debugSseConnector = null;
  });

  /// 构造带延迟的历史/工具接口 mock（issue #38 多会话端点）：
  /// 会话列表立即返回（含 id=1 会话或空列表），会话详情在
  /// [historyDelay] 毫秒后返回，用于把布局更新精确落在自动聚焦
  /// （320ms）窗口内。
  MockClient delayedHistoryClient({
    required Duration historyDelay,
    List<Map<String, dynamic>>? messages,
  }) {
    return MockClient((request) async {
      final path = request.url.path;
      // 会话列表（issue #38）：立即返回，用于历史按钮显隐与恢复最近会话
      if (path.endsWith('/admin/agent/chat-sessions') &&
          !path.endsWith('/chat-sessions/')) {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'sessions': messages == null
                  ? []
                  : [
                      {
                        'id': 1,
                        'title': '历史会话',
                        'updated_at': '2026-08-16T12:00:00+08:00',
                      },
                    ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
      }
      // 会话详情（issue #38）：延迟返回，模拟历史消息在聚焦窗口内到达
      if (RegExp(r'/admin/agent/chat-sessions/\d+$').hasMatch(path) &&
          request.method == 'GET') {
        await Future<void>.delayed(historyDelay);
        return http.Response(
          jsonEncode({
            'id': 1,
            'title': '历史会话',
            'messages': messages ?? [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      // 旧端点兼容（issue #32）
      if (path.endsWith('/admin/agent/chat-history')) {
        if (request.method == 'GET') {
          await Future<void>.delayed(historyDelay);
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
      return http.Response('not found', 404);
    });
  }

  /// 工具列表 mock（与 agent_chat_history_test.dart 一致）。
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
      tools: const [
        AgentToolMeta(
          name: 'list_containers',
          description: '列出所有容器',
          group: '容器',
          parameters: {},
        ),
      ],
    );
  }

  /// 打开聊天窗口（右边栏分支，与右上角按钮路径一致）并逐帧推进
  /// 滑入动画（260ms）至自动聚焦时刻（320ms），随后多帧渲染。
  Future<void> openChatWithTimeline(
    WidgetTester tester, {
    required MockClient client,
  }) async {
    SharedPreferences.setMockInitialValues({
      'web_backend_url': 'https://example.com',
      'web_backend_token': 'test-key',
    });
    AgentService.debugHttpClient = client;
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
    // 逐帧推进滑入动画（260ms）与自动聚焦定时器（320ms），
    // 每 10ms 一帧精确模拟 Web 上动画期间逐帧渲染的时序
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    // 动画结束后再推进几帧：工具加载 setState + 焦点变化帧
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  group('issue #37 打开对话框 null check 复现', () {
    testWidgets('历史消息加载落在聚焦窗口内（300ms 返回 + 320ms 聚焦）不崩溃',
        (tester) async {
      final client = delayedHistoryClient(
        historyDelay: const Duration(milliseconds: 300),
        messages: [
          {'role': 'user', 'content': '历史问题'},
          {'role': 'assistant', 'content': '历史回复'},
        ],
      );
      await openChatWithTimeline(tester, client: client);

      // 历史消息与新会话按钮正常渲染
      expect(find.text('历史问题'), findsOneWidget);
      expect(find.text('历史回复'), findsOneWidget);
      expect(find.byKey(const Key('agent_new_session_button')), findsOneWidget);
      // 输入框在自动聚焦时序后获得焦点（右边栏 autofocusInput）
      final field = tester.widget<TextField>(
          find.byKey(const Key('agent_input_field')));
      expect(field.focusNode!.hasFocus, isTrue);
      // 全程无未捕获异常（null check 崩溃会让本断言失败）
      expect(tester.takeException(), isNull);
    });

    testWidgets('聚焦刚建立后历史布局更新（360ms 返回）不崩溃', (tester) async {
      final client = delayedHistoryClient(
        historyDelay: const Duration(milliseconds: 360),
        messages: [
          {'role': 'user', 'content': '聚焦后到达的问题'},
          {'role': 'assistant', 'content': '聚焦后到达的回复'},
        ],
      );
      await openChatWithTimeline(tester, client: client);

      expect(find.text('聚焦后到达的问题'), findsOneWidget);
      expect(find.byKey(const Key('agent_new_session_button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('无历史消息时打开对话框不崩溃（空状态路径）', (tester) async {
      final client = delayedHistoryClient(
        historyDelay: const Duration(milliseconds: 50),
      );
      await openChatWithTimeline(tester, client: client);

      expect(find.text('有什么可以帮你？'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('历史消息含工具步骤 steps 时打开对话框不崩溃', (tester) async {
      final client = delayedHistoryClient(
        historyDelay: const Duration(milliseconds: 280),
        messages: [
          {'role': 'user', 'content': '帮我拉镜像'},
          {
            'role': 'assistant',
            'content': '已拉取',
            'steps': [
              {
                'type': 'step',
                'name': 'docker_mirror_pull',
                'arguments': {'image': 'nginx'},
              },
              {
                'type': 'step_result',
                'name': 'docker_mirror_pull',
                'result': 'ok',
              },
            ],
          },
        ],
      );
      await openChatWithTimeline(tester, client: client);

      expect(find.text('帮我拉镜像'), findsOneWidget);
      expect(find.byKey(const Key('agent_new_session_button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('右上角 AppBar 按钮打开对话框完整路径不崩溃', (tester) async {
      SharedPreferences.setMockInitialValues({
        'web_backend_url': 'https://example.com',
        'web_backend_token': 'test-key',
      });
      AgentService.debugHttpClient = delayedHistoryClient(
        historyDelay: const Duration(milliseconds: 300),
        messages: [
          {'role': 'user', 'content': '右上角按钮打开'},
          {'role': 'assistant', 'content': '正常回复'},
        ],
      );
      AgentService.debugFetchToolsOverride = fakeFetchTools;
      await tester.pumpWidget(buildTestApp(
        home: const MainTabScreen(),
        locale: const Locale('zh'),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byKey(const Key('agent_appbar_button')));
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.byKey(const Key('agent_chat_screen')), findsOneWidget);
      expect(find.text('右上角按钮打开'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
