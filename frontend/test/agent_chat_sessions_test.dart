import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/agent_chat_screen.dart';
import 'package:mobile_portainer_flutter_module/services/agent_service.dart';
import 'test_utils.dart';

/// AI 助手聊天框「历史会话」功能（issue #38）。
///
/// 需求（用户澄清，方案B）：聊天窗口头部增加历史入口，历史列表以
/// 右侧栏形式展示；标题取首条用户消息摘要；最多保留 100 条；
/// 支持删除单条历史；无历史时入口隐藏；历史加载失败提示网络问题；
/// 点击某条恢复该对话并可继续追问。
///
/// 覆盖：
/// - 历史按钮显隐：有会话显示、无会话隐藏、加载失败隐藏
/// - 历史右侧栏：打开显示会话列表（标题+时间）、关闭按钮、遮罩点击关闭
/// - 恢复会话：点击列表项替换当前对话并设置当前会话 id、
///   恢复失败提示
/// - 删除单条：确认对话框（分端）、删除后列表更新、删除当前会话清空对话
/// - 会话 id 事件：首次对话收到 session_id 后历史按钮出现
/// 默认会话列表（两个历史会话，最新在前）。
const _defaultSessions = [
  {
    'id': 1,
    'title': '帮我拉取 nginx 镜像',
    'updated_at': '2026-08-16T10:00:00+08:00',
  },
  {
    'id': 2,
    'title': '查看容器日志',
    'updated_at': '2026-08-15T09:30:00+08:00',
  },
];

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

  /// 会话列表 mock：sessions 为 null 时返回默认列表（有历史）。
  MockClient sessionClient({
    List<Map<String, dynamic>>? sessions,
    List<Map<String, dynamic>>? sessionsAfter, // 首次之后的列表（验证会话落库后刷新）
    List<Map<String, dynamic>>? messages, // 会话详情消息
    bool failLoad = false,
    bool failDetail = false,
    void Function(int)? onDeleteCalled,
    void Function()? onSnapshotCalled,
  }) {
    var listCalls = 0;
    return MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/admin/agent/chat-sessions') &&
          !path.endsWith('/chat-sessions/')) {
        if (request.method == 'GET') {
          if (failLoad) return http.Response('server error', 500);
          listCalls++;
          final list = listCalls == 1
              ? (sessions ?? _defaultSessions)
              : (sessionsAfter ?? sessions ?? _defaultSessions);
          return http.Response(
            jsonEncode({'sessions': list}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST') {
          onSnapshotCalled?.call();
          return http.Response(
            jsonEncode({
              'id': 99,
              'title': '快照会话',
              'updated_at': '2026-08-16T12:00:00+08:00',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
      }
      // 会话详情
      final detailMatch =
          RegExp(r'/admin/agent/chat-sessions/(\d+)$').firstMatch(path);
      if (detailMatch != null) {
        final id = int.parse(detailMatch.group(1)!);
        if (request.method == 'GET') {
          if (failDetail) return http.Response('server error', 500);
          return http.Response(
            jsonEncode({
              'id': id,
              'title': '历史会话 $id',
              'messages': messages ?? [
                {'role': 'user', 'content': '会话 $id 的问题'},
                {'role': 'assistant', 'content': '会话 $id 的回复'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'DELETE') {
          onDeleteCalled?.call(id);
          return http.Response(
              jsonEncode({'deleted': 1}), 200,
              headers: {'content-type': 'application/json'});
        }
      }
      if (path.endsWith('/admin/agent/tools')) {
        return http.Response(
          jsonEncode({'skills': [], 'tools': []}),
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
    Locale locale = const Locale('zh'),
  }) async {
    SharedPreferences.setMockInitialValues({
      'web_backend_url': 'https://example.com',
      'web_backend_token': 'test-key',
    });
    AgentService.debugHttpClient = client ?? sessionClient();
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
      locale: locale,
    ));
    await tester.tap(find.text('open-chat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // 滑入动画
    await tester.pump(); // 历史加载 setState 后的帧
    await tester.pump();
  }

  group('历史入口显隐（issue #38）', () {
    testWidgets('有历史会话时头部显示历史按钮', (tester) async {
      await pumpChatScreen(tester, client: sessionClient());

      expect(find.byKey(const Key('agent_history_button')), findsOneWidget,
          reason: '有历史会话时头部应显示历史按钮');
    });

    testWidgets('无历史会话时头部隐藏历史按钮', (tester) async {
      await pumpChatScreen(tester, client: sessionClient(sessions: []));

      expect(find.byKey(const Key('agent_history_button')), findsNothing,
          reason: '无历史会话时历史入口应隐藏');
      expect(find.text('有什么可以帮你？'), findsOneWidget);
    });

    testWidgets('历史加载失败时隐藏历史按钮且不阻塞聊天', (tester) async {
      await pumpChatScreen(tester, client: sessionClient(failLoad: true));

      expect(find.byKey(const Key('agent_history_button')), findsNothing,
          reason: '加载失败视为无历史，入口隐藏');
      expect(find.byKey(const Key('agent_input_field')), findsOneWidget,
          reason: '历史加载失败不影响正常聊天');
      expect(find.text('有什么可以帮你？'), findsOneWidget);
    });
  });

  group('历史右侧栏（issue #38）', () {
    testWidgets('点击历史按钮打开右侧栏，展示会话列表（标题+时间）', (tester) async {
      await pumpChatScreen(tester, client: sessionClient());
      await tester.tap(find.byKey(const Key('agent_history_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // 面板滑入动画

      expect(find.byKey(const Key('agent_history_panel')), findsOneWidget,
          reason: '历史右侧栏应展开');
      expect(find.text('帮我拉取 nginx 镜像'), findsOneWidget);
      expect(find.text('查看容器日志'), findsOneWidget);
      expect(find.text('2026-08-16 10:00'), findsOneWidget,
          reason: '会话时间应格式化展示（本地时间）');
    });

    testWidgets('点击遮罩关闭历史右侧栏', (tester) async {
      await pumpChatScreen(tester, client: sessionClient());
      await tester.tap(find.byKey(const Key('agent_history_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('agent_history_panel')), findsOneWidget);

      await tester.tap(find.byKey(const Key('agent_history_backdrop')),
          warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(); // 滑出动画结束：面板从树中移除
      expect(find.text('帮我拉取 nginx 镜像'), findsNothing);
    });

    testWidgets('历史加载失败时右侧栏展示网络提示并可重试', (tester) async {
      await pumpChatScreen(tester, client: sessionClient());
      // 打开面板时列表加载失败
      AgentService.debugHttpClient = sessionClient(failLoad: true);
      await tester.tap(find.byKey(const Key('agent_history_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('历史加载失败，请检查网络后重试'), findsOneWidget,
          reason: '加载失败应提示网络问题');
      expect(find.byKey(const Key('agent_history_retry')), findsOneWidget,
          reason: '失败态应提供重试入口');
    });
  });

  group('恢复会话（issue #38）', () {
    testWidgets('点击列表项恢复该会话并可继续追问', (tester) async {
      await pumpChatScreen(tester, client: sessionClient());
      // 打开时自动恢复最近会话（id=1）
      expect(find.text('会话 1 的问题'), findsOneWidget);
      expect(find.text('会话 1 的回复'), findsOneWidget);

      // 打开历史面板，点击 id=2 的会话恢复
      await tester.tap(find.byKey(const Key('agent_history_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('agent_history_item_2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(); // 滑出动画结束：面板从树中移除

      expect(find.text('会话 2 的问题'), findsOneWidget,
          reason: '应恢复 id=2 会话的消息');
      expect(find.text('会话 2 的回复'), findsOneWidget);
      expect(find.text('会话 1 的问题'), findsNothing,
          reason: '当前对话应被替换为恢复的会话');
      // 面板已关闭并从树中移除
      expect(find.text('帮我拉取 nginx 镜像'), findsNothing);
    });

    testWidgets('恢复会话失败时提示恢复失败', (tester) async {
      await pumpChatScreen(tester, client: sessionClient());
      // 打开面板后详情接口失败
      AgentService.debugHttpClient = sessionClient(failDetail: true);
      await tester.tap(find.byKey(const Key('agent_history_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('agent_history_item_2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('恢复会话失败，请重试'), findsOneWidget,
          reason: '恢复失败应提示，不崩溃');
    });
  });

  group('删除单条历史（issue #38）', () {
    testWidgets('删除历史会话：确认后列表移除，非当前会话不清空对话', (tester) async {
      final deletedIds = <int>[];
      await pumpChatScreen(
        tester,
        client: sessionClient(
          onDeleteCalled: (id) => deletedIds.add(id),
        ),
      );
      await tester.tap(find.byKey(const Key('agent_history_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 删除 id=2（非当前会话）
      await tester.tap(find.byKey(const Key('agent_history_delete_2')));
      await tester.pump();
      expect(find.byKey(const Key('agent_history_delete_confirm')),
          findsOneWidget,
          reason: '删除前应弹出确认框');
      await tester.tap(find.text('删除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(deletedIds, [2], reason: '应调用 DELETE 删除 id=2 会话');
      expect(find.text('查看容器日志'), findsNothing,
          reason: '删除后列表应移除该会话');
      expect(find.text('帮我拉取 nginx 镜像'), findsOneWidget,
          reason: '其他会话保留');
      // 当前对话（恢复的 id=1 会话）不受影响
      expect(find.text('会话 1 的问题'), findsOneWidget);
    });

    testWidgets('删除当前活跃会话后清空当前对话', (tester) async {
      final deletedIds = <int>[];
      await pumpChatScreen(
        tester,
        client: sessionClient(
          messages: [
            {'role': 'user', 'content': '当前会话消息'},
            {'role': 'assistant', 'content': '当前会话回复'},
          ],
          onDeleteCalled: (id) => deletedIds.add(id),
        ),
      );
      // 打开时自动恢复 id=1 会话（当前活跃会话）
      expect(find.text('当前会话消息'), findsOneWidget);

      await tester.tap(find.byKey(const Key('agent_history_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('agent_history_delete_1')));
      await tester.pump();
      await tester.tap(find.text('删除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(deletedIds, [1]);
      expect(find.text('当前会话消息'), findsNothing,
          reason: '删除当前会话后应清空当前对话');
      expect(find.text('有什么可以帮你？'), findsOneWidget,
          reason: '回到空状态');
    });
  });

  group('会话 id 事件（issue #38）', () {
    testWidgets('无历史时首次对话收到 session_id 后历史按钮出现', (tester) async {
      // 无历史打开；收到 session_id 后列表刷新返回新会话
      await pumpChatScreen(
        tester,
        client: sessionClient(
          sessions: [],
          sessionsAfter: [
            {
              'id': 7,
              'title': '帮我查看容器',
              'updated_at': '2026-08-16T12:00:00+08:00',
            },
          ],
        ),
      );
      expect(find.byKey(const Key('agent_history_button')), findsNothing,
          reason: '前置条件：无历史时无历史按钮');

      // 流式回复：完成后推送 session_id 事件
      AgentService.debugSseConnector = (uri, headers, {body, ignoreSsl = false}) {
        return Stream.fromIterable([
          'event: token\ndata: {"content": "好的，已执行"}',
          'event: reply\ndata: {"content": "好的，已执行"}',
          'event: session_id\ndata: {"session_id": 7}',
          'event: done\ndata: {}',
        ]);
      };
      await tester.enterText(find.byType(TextField), '帮我查看容器');
      await tester.pump();
      await tester.tap(find.byKey(const Key('agent_send_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('好的，已执行'), findsOneWidget);
      // 会话 id 事件触发列表刷新 → 历史按钮出现
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('agent_history_button')), findsOneWidget,
          reason: '首次对话落库后应出现历史入口');
    });
  });
}
