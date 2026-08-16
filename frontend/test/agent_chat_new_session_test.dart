import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/agent_chat_screen.dart';
import 'package:mobile_portainer_flutter_module/services/agent_service.dart';
import 'test_utils.dart';

/// AI 助手聊天框「打开新会话」按钮（issue #36/#38）。
///
/// 需求：右边栏的聊天框后增加一个打开新会话的按钮，点击之后打开新会话。
/// issue #38 起：历史由多会话列表管理，「打开新会话」不再清空后端历史，
/// 而是结束当前会话（已实时保存）；当前对话尚未落库时快照保存为一条
/// 历史会话后再清空。
///
/// 覆盖：
/// - 正常路径：有消息时按钮显示在聊天框后（消息列表末尾）；
///   点击后清空消息回到空状态，历史会话保留
/// - 边界场景：无消息（空状态）时不显示按钮；发送中点击中断流式
///   回复且状态复位（可继续发送）并快照保存未落库对话；点击后输入框
///   获得焦点可直接输入；英文 locale 显示英文文案
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

  /// 注入返回固定响应的 http client（issue #38 多会话端点）。
  ///
  /// - GET /chat-sessions：messages 非空时返回含 id=1 的会话，否则空列表
  /// - GET /chat-sessions/1：返回 messages 作为会话完整消息
  /// - POST /chat-sessions：快照保存，调用 onSnapshotCalled 并返回 id=99
  MockClient historyClient({
    List<Map<String, dynamic>>? messages,
    void Function()? onSnapshotCalled,
  }) {
    return MockClient((request) async {
      final path = request.url.path;
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
      if (RegExp(r'/admin/agent/chat-sessions/\d+$').hasMatch(path) &&
          request.method == 'GET') {
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
      if (path.endsWith('/admin/agent/tools')) {
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

  /// 打开聊天窗口（带历史注入）并等待滑入动画与历史加载完成。
  Future<void> pumpChatScreen(
    WidgetTester tester, {
    MockClient? client,
    Locale locale = const Locale('zh'),
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
      locale: locale,
    ));
    await tester.tap(find.text('open-chat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // 滑入动画
    await tester.pump(); // 历史加载 setState 后的帧
    await tester.pump();
  }

  testWidgets('有消息时按钮显示在聊天框后（消息列表末尾）', (tester) async {
    await pumpChatScreen(
      tester,
      client: historyClient(messages: [
        {'role': 'user', 'content': '第一条消息'},
        {'role': 'assistant', 'content': '第一条回复'},
      ]),
    );

    final button = find.byKey(const Key('agent_new_session_button'));
    expect(button, findsOneWidget, reason: '有消息时聊天框后应显示新会话按钮');
    expect(find.text('打开新会话'), findsOneWidget, reason: '按钮文案应为打开新会话');

    // 位置断言：按钮位于最后一条消息下方（聊天框后，而非头部）
    final lastMsgY = tester.getCenter(find.text('第一条回复')).dy;
    final buttonY = tester.getCenter(button).dy;
    expect(buttonY, greaterThan(lastMsgY),
        reason: '新会话按钮应位于聊天消息之后');
  });

  testWidgets('无消息（空状态）时不显示新会话按钮', (tester) async {
    await pumpChatScreen(tester, client: historyClient());

    expect(find.text('有什么可以帮你？'), findsOneWidget);
    expect(find.byKey(const Key('agent_new_session_button')), findsNothing,
        reason: '空会话时无需新会话按钮（空状态本身即新会话）');
  });

  testWidgets('点击新会话按钮清空消息回到空状态，历史会话保留', (tester) async {
    var snapshotCalls = 0;
    await pumpChatScreen(
      tester,
      client: historyClient(
        messages: [
          {'role': 'user', 'content': '待清空消息'},
          {'role': 'assistant', 'content': '待清空回复'},
        ],
        onSnapshotCalled: () => snapshotCalls++,
      ),
    );

    expect(find.text('待清空消息'), findsOneWidget);
    await tester.tap(find.byKey(const Key('agent_new_session_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    // 前端消息清空，回到空状态
    expect(find.text('待清空消息'), findsNothing, reason: '新会话后消息应清空');
    expect(find.text('有什么可以帮你？'), findsOneWidget,
        reason: '新会话后应回到空状态');
    // issue #38：当前对话已实时保存为历史会话（id=1），无需快照，
    // 且历史不被清空——历史按钮仍显示
    expect(snapshotCalls, 0,
        reason: '已落库的会话打开新会话时无需再次快照');
    expect(find.byKey(const Key('agent_history_button')), findsOneWidget,
        reason: '历史会话应保留（历史按钮仍显示）');
  });

  testWidgets('发送中点击新会话：中断流式回复、状态复位可继续发送', (tester) async {
    // 延迟完成的事件流：验证发送中点击新会话可中断
    Stream<String> delayedStream() async* {
      yield 'event: token\ndata: {"content": "处理中"}';
      await Future<void>.delayed(const Duration(milliseconds: 500));
      yield 'event: reply\ndata: {"content": "迟到的回复"}';
      yield 'event: done\ndata: {}';
    }

    AgentService.debugSseConnector = (uri, headers, {body, ignoreSsl = false}) {
      return delayedStream();
    };
    var snapshotCalls = 0;
    await pumpChatScreen(
      tester,
      client: historyClient(onSnapshotCalled: () => snapshotCalls++),
    );

    // 发送一条消息，进入发送中状态
    await tester.enterText(find.byType(TextField), '帮我看看容器');
    await tester.pump();
    await tester.tap(find.byKey(const Key('agent_send_button')));
    await tester.pump();
    expect(find.text('思考中…'), findsOneWidget, reason: '前置条件：发送中');

    // 发送中点击新会话：中断流式并清空
    await tester.tap(find.byKey(const Key('agent_new_session_button')));
    await tester.pump();

    expect(find.text('帮我看看容器'), findsNothing, reason: '新会话应清空发送中的消息');
    expect(find.text('有什么可以帮你？'), findsOneWidget,
        reason: '新会话后应回到空状态');
    expect(snapshotCalls, 1,
        reason: '未落库的当前对话打开新会话前应快照保存到历史');

    // 流式残留事件到达后不崩溃、不复活旧消息
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('迟到的回复'), findsNothing,
        reason: '中断后的迟到 token 不应渲染到新会话');

    // 状态复位：新会话立即可发送
    await tester.enterText(find.byType(TextField), '新会话第一条');
    await tester.pump();
    final sendBtn = tester.widget<IconButton>(find.byKey(const Key('agent_send_button')));
    expect(sendBtn.onPressed, isNotNull, reason: '新会话后发送状态应复位可继续发送');
    await tester.tap(find.byKey(const Key('agent_send_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('新会话第一条'), findsOneWidget, reason: '新会话第一条消息应上屏');

    // 让第二条消息流内的延迟 timer 全部结束，避免测试结束时 pending
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('点击新会话后输入框获得焦点，可直接输入', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await pumpChatScreen(
        tester,
        client: historyClient(messages: [
          {'role': 'user', 'content': '旧消息'},
          {'role': 'assistant', 'content': '旧回复'},
        ]),
      );

      final inputField = find.byKey(const Key('agent_input_field'));
      final focusNode = tester.widget<TextField>(inputField).focusNode!;

      // 点击按钮会短暂夺走焦点，延迟重聚焦后应回到输入框
      await tester.tap(find.byKey(const Key('agent_new_session_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();

      expect(focusNode.hasFocus, isTrue,
          reason: '打开新会话后输入框应获得焦点，可直接开始输入');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('重复点击新会话幂等（清空后按钮消失）', (tester) async {
    var snapshotCalls = 0;
    await pumpChatScreen(
      tester,
      client: historyClient(
        messages: [
          {'role': 'user', 'content': '消息 A'},
          {'role': 'assistant', 'content': '回复 A'},
        ],
        onSnapshotCalled: () => snapshotCalls++,
      ),
    );

    // 第一次点击：清空并回到空状态
    await tester.tap(find.byKey(const Key('agent_new_session_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    // 清空后按钮随消息列表消失，不存在第二次点击入口
    expect(find.byKey(const Key('agent_new_session_button')), findsNothing,
        reason: '清空后新会话按钮应消失');
    expect(snapshotCalls, 0,
        reason: '已落库会话无需快照，历史不被重复保存');
  });

  testWidgets('英文 locale 下按钮显示英文文案', (tester) async {
    await pumpChatScreen(
      tester,
      client: historyClient(messages: [
        {'role': 'user', 'content': 'hello'},
        {'role': 'assistant', 'content': 'hi there'},
      ]),
      locale: const Locale('en'),
    );

    expect(find.byKey(const Key('agent_new_session_button')), findsOneWidget);
    expect(find.text('New chat'), findsOneWidget,
        reason: '英文环境新会话按钮应为英文文案');
  });
}
