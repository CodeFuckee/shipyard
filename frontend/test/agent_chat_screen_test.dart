import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/agent_chat_screen.dart';
import 'package:mobile_portainer_flutter_module/screens/main_tab_screen.dart';
import 'package:mobile_portainer_flutter_module/services/agent_service.dart';
import 'test_utils.dart';

/// AI agent 聊天框测试（issue #21）。
///
/// 覆盖：
/// - 正常路径：导航栏正中间显示 AI 按钮、点击弹出聊天框（VM 环境走居中
///   dialog 分支）、发送消息后流式渲染回复、工具选择器渲染
/// - 边界情况：空输入发送按钮禁用、流式 token 逐步更新、error 事件提示、
///   tools 加载失败显示重试、发送中禁止重复发送
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    AgentService.debugSseConnector = null;
    AgentService.debugHttpClient = null;
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
        AgentToolMeta(
          name: 'docker_pull_from_file',
          description: '批量拉取镜像',
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

  Future<void> pumpChatScreen(
    WidgetTester tester, {
    Future<AgentToolsInfo> Function()? fetchTools,
  }) async {
    // 后端地址与 token：_resolveBackend 需要 prefs 有值
    SharedPreferences.setMockInitialValues({
      'web_backend_url': 'https://example.com',
      'web_backend_token': 'test-key',
    });
    AgentService.debugFetchToolsOverride = fetchTools ?? fakeFetchTools;
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
    await tester.pump(const Duration(milliseconds: 100));
    // 额外一帧：_loadTools 的 setState 可能在上一帧渲染后标记
    await tester.pump();
  }

  testWidgets('底部导航栏正中间显示 AI agent 按钮', (tester) async {
    await tester.pumpWidget(buildTestApp(
      home: const MainTabScreen(),
      locale: const Locale('zh'),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    final navBar = find.byKey(const Key('main_bottom_nav_bar'));
    expect(navBar, findsOneWidget);
    final agentBtn = find.descendant(
      of: navBar,
      matching: find.byKey(const Key('agent_chat_button')),
    );
    expect(agentBtn, findsOneWidget, reason: '导航栏应有 AI agent 按钮');

    // 正中间：AI 按钮在"资源"与"项目"之间（水平位置居中）
    final resources = find.descendant(of: navBar, matching: find.text('资源'));
    final projects = find.descendant(of: navBar, matching: find.text('项目'));
    final btnX = tester.getCenter(agentBtn).dx;
    final resourcesX = tester.getCenter(resources).dx;
    final projectsX = tester.getCenter(projects).dx;
    expect(btnX, greaterThan(resourcesX));
    expect(btnX, lessThan(projectsX));

    // 原有 4 个 tab 仍存在
    for (final label in ['概览', '资源', '项目', '设置']) {
      expect(
        find.descendant(of: navBar, matching: find.text(label)),
        findsOneWidget,
      );
    }
  });

  testWidgets('点击 AI 按钮后底栏原位展开输入框，并可关闭恢复导航', (tester) async {
    await tester.pumpWidget(buildTestApp(
      home: const MainTabScreen(),
      locale: const Locale('zh'),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const Key('agent_chat_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('bottom_agent_input')), findsOneWidget,
        reason: '点击 AI 按钮后应在底栏原位展开输入框');
    expect(find.byKey(const Key('bottom_agent_close')), findsOneWidget,
        reason: '展开输入框后应提供返回导航按钮');
    expect(find.byKey(const Key('agent_chat_button')), findsNothing,
        reason: '展开状态不应保留 AI 入口按钮');
    final sendBtn = tester.widget<IconButton>(
      find.byKey(const Key('bottom_agent_send')),
    );
    expect(sendBtn.onPressed, isNull, reason: '底栏空输入时发送按钮应禁用');

    await tester.tap(find.byKey(const Key('bottom_agent_close')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('agent_chat_button')), findsOneWidget,
        reason: '关闭后应恢复底部导航栏');
  });

  testWidgets('底栏发送消息后打开聊天框并自动发送首条消息', (tester) async {
    AgentService.debugFetchToolsOverride = fakeFetchTools;
    AgentService.debugSseConnector = (uri, headers, {body, ignoreSsl = false}) {
      return const Stream<String>.empty();
    };
    await tester.pumpWidget(buildTestApp(
      home: const MainTabScreen(),
      locale: const Locale('zh'),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('agent_chat_button')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const Key('bottom_agent_input')),
      '帮我检查容器状态',
    );
    await tester.pump();
    expect(
      tester.widget<IconButton>(find.byKey(const Key('bottom_agent_send'))).onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('bottom_agent_send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AgentChatScreen), findsOneWidget,
        reason: '发送后应打开完整聊天框');
    expect(find.byType(AlertDialog), findsOneWidget,
        reason: 'VM（非手机端）环境应使用居中 dialog');
    expect(find.text('帮我检查容器状态'), findsOneWidget,
        reason: '聊天框应自动发送底栏输入的首条消息');
  });

  testWidgets('聊天框渲染输入框、发送按钮与工具选择器', (tester) async {
    await pumpChatScreen(tester);

    expect(find.byType(TextField), findsOneWidget);
    final sendBtn = tester.widget<IconButton>(find.byKey(const Key('agent_send_button')));
    expect(sendBtn.onPressed, isNull, reason: '空输入时发送按钮应禁用');

    // 工具选择器：skills 默认勾选 + tools 可选
    expect(find.text('docker_mirror_pull'), findsOneWidget);
    expect(find.text('list_containers'), findsOneWidget);
  });

  testWidgets('输入文本后发送按钮可用，点击发送渲染用户消息', (tester) async {
    AgentService.debugSseConnector = (uri, headers, {body, ignoreSsl = false}) {
      return const Stream<String>.empty();
    };
    await pumpChatScreen(tester);

    await tester.enterText(find.byType(TextField), '帮我看看容器');
    await tester.pump();
    final sendBtn = tester.widget<IconButton>(find.byKey(const Key('agent_send_button')));
    expect(sendBtn.onPressed, isNotNull, reason: '输入后发送按钮应可用');

    await tester.tap(find.byKey(const Key('agent_send_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('帮我看看容器'), findsOneWidget, reason: '用户消息应上屏');
  });

  testWidgets('流式 token 事件逐步更新回复文本', (tester) async {
    AgentService.debugSseConnector = (uri, headers, {body, ignoreSsl = false}) {
      return Stream<String>.fromIterable(const [
        'event: token\ndata: {"content": "你"}',
        'event: token\ndata: {"content": "好"}',
        'event: step\ndata: {"name": "list_containers", "arguments": {}}',
        'event: step_result\ndata: {"name": "list_containers", "result": "ok"}',
        'event: reply\ndata: {"content": "你好"}',
        'event: done\ndata: {}',
      ]);
    };
    await pumpChatScreen(tester);

    await tester.enterText(find.byType(TextField), '看看容器');
    await tester.pump();
    await tester.tap(find.byKey(const Key('agent_send_button')));
    await tester.pump();

    // token 逐个到达：第一次 pump 后出现"你"
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // 最终完整回复
    expect(find.text('你好'), findsOneWidget, reason: '流式结束后应显示完整回复');
  });

  testWidgets('error 事件显示错误提示', (tester) async {
    AgentService.debugSseConnector = (uri, headers, {body, ignoreSsl = false}) {
      return Stream<String>.fromIterable(const [
        'event: error\ndata: {"message": "LLM 服务不可用"}',
      ]);
    };
    await pumpChatScreen(tester);

    await tester.enterText(find.byType(TextField), 'hi');

    await tester.pump();
    await tester.tap(find.byKey(const Key('agent_send_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('LLM 服务不可用'), findsOneWidget,
        reason: '错误事件应在界面提示');
  });

  testWidgets('连接异常（断流）显示错误提示', (tester) async {
    AgentService.debugSseConnector = (uri, headers, {body, ignoreSsl = false}) {
      return Stream<String>.error(Exception('网络连接失败'));
    };
    await pumpChatScreen(tester);

    await tester.enterText(find.byType(TextField), 'hi');

    await tester.pump();
    await tester.tap(find.byKey(const Key('agent_send_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('网络连接失败'), findsOneWidget,
        reason: '连接异常应在界面提示');
  });

  testWidgets('HTTP 422 流错误显示可读提示（不暴露原始 JSON）', (tester) async {
    AgentService.debugSseConnector = (uri, headers, {body, ignoreSsl = false}) {
      return Stream<String>.error(Exception(
          'HTTP 422: {"detail":[{"type":"model_attributes_type",'
          '"loc":["body"],"msg":"Input should be a valid dictionary '
          'or object to extract fields from"}]}'));
    };
    await pumpChatScreen(tester);

    await tester.enterText(find.byType(TextField), 'hi');

    await tester.pump();
    await tester.tap(find.byKey(const Key('agent_send_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('HTTP 422'), findsOneWidget,
        reason: '422 错误应在界面提示用户');
    expect(find.textContaining('model_attributes_type'), findsNothing,
        reason: '后端原始错误 JSON 不应展示给用户');
  });

  testWidgets('tools 加载失败显示重试按钮，点击重试成功', (tester) async {
    var attempts = 0;
    await pumpChatScreen(tester, fetchTools: () async {
      attempts++;
      if (attempts == 1) {
        throw Exception('加载失败');
      }
      return fakeFetchTools();
    });

    expect(find.textContaining('加载失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(); // 成功路径的 setState 同样需要额外一帧
    expect(find.text('docker_mirror_pull'), findsOneWidget,
        reason: '重试后工具列表应加载成功');
  });

  testWidgets('发送中禁止重复发送，结束后恢复', (tester) async {
    // 延迟完成的事件流，验证发送中按钮禁用
    Stream<String> delayedStream() async* {
      yield 'event: token\ndata: {"content": "处理中"}';
      await Future<void>.delayed(const Duration(milliseconds: 300));
      yield 'event: done\ndata: {}';
    }

    AgentService.debugSseConnector = (uri, headers, {body, ignoreSsl = false}) {
      return delayedStream();
    };
    await pumpChatScreen(tester);

    await tester.enterText(find.byType(TextField), 'hi');

    await tester.pump();
    await tester.tap(find.byKey(const Key('agent_send_button')));
    await tester.pump();

    // 发送中：按钮禁用
    final sendBtn = tester.widget<IconButton>(find.byKey(const Key('agent_send_button')));
    expect(sendBtn.onPressed, isNull, reason: '发送中应禁止重复发送');

    // 发送完成后输入框已清空，按钮仍禁用
    await tester.pump(const Duration(milliseconds: 400));
    final sendBtn2 = tester.widget<IconButton>(find.byKey(const Key('agent_send_button')));
    expect(sendBtn2.onPressed, isNull, reason: '发送后输入框清空，按钮应禁用');

    // 重新输入后可再次发送（证明发送状态已复位）
    await tester.enterText(find.byType(TextField), '第二条消息');
    await tester.pump();
    final sendBtn3 = tester.widget<IconButton>(find.byKey(const Key('agent_send_button')));
    expect(sendBtn3.onPressed, isNotNull, reason: '发送完成后按钮应恢复');
  });

  testWidgets('空状态显示引导文案（Codex 风格）', (tester) async {
    await pumpChatScreen(tester);

    expect(find.text('有什么可以帮你？'), findsOneWidget,
        reason: '空状态应显示引导标题');
    expect(find.textContaining('描述你的需求'), findsOneWidget,
        reason: '空状态应显示引导描述');
  });

  testWidgets('消息带角色标签：用户"你"、助手"AI 助手"', (tester) async {
    AgentService.debugSseConnector = (uri, headers, {body, ignoreSsl = false}) {
      return const Stream<String>.empty();
    };
    await pumpChatScreen(tester);

    await tester.enterText(find.byType(TextField), '帮我看看容器');
    await tester.pump();
    await tester.tap(find.byKey(const Key('agent_send_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('你'), findsOneWidget, reason: '用户消息应带"你"标签');
    // 助手标签与 header 标题相同（AI 助手），共 2 处
    expect(find.text('AI 助手'), findsNWidgets(2),
        reason: '助手消息标签 + header 标题');
  });

  testWidgets('有消息时显示清空按钮，点击清空回到空状态', (tester) async {
    AgentService.debugSseConnector = (uri, headers, {body, ignoreSsl = false}) {
      return const Stream<String>.empty();
    };
    await pumpChatScreen(tester);

    // 初始无消息：清空按钮不显示
    expect(find.byKey(const Key('agent_clear_button')), findsNothing);

    await tester.enterText(find.byType(TextField), 'hi');
    await tester.pump();
    await tester.tap(find.byKey(const Key('agent_send_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('agent_clear_button')), findsOneWidget,
        reason: '有消息时显示清空按钮');
    expect(find.text('hi'), findsOneWidget);

    await tester.tap(find.byKey(const Key('agent_clear_button')));
    await tester.pump();

    expect(find.text('hi'), findsNothing, reason: '清空后消息应消失');
    expect(find.text('有什么可以帮你？'), findsOneWidget,
        reason: '清空后回到空状态');
  });

  testWidgets('发送中显示"思考中"状态条', (tester) async {
    Stream<String> delayedStream() async* {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      yield 'event: done\ndata: {}';
    }

    AgentService.debugSseConnector = (uri, headers, {body, ignoreSsl = false}) {
      return delayedStream();
    };
    await pumpChatScreen(tester);

    await tester.enterText(find.byType(TextField), 'hi');
    await tester.pump();
    await tester.tap(find.byKey(const Key('agent_send_button')));
    await tester.pump();

    expect(find.text('思考中…'), findsOneWidget, reason: '发送中应显示思考状态');
    expect(find.byKey(const Key('agent_thinking_indicator')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('思考中…'), findsNothing, reason: '完成后状态条应消失');
  });

  testWidgets('工具执行步骤渲染为徽章', (tester) async {
    AgentService.debugSseConnector = (uri, headers, {body, ignoreSsl = false}) {
      return Stream<String>.fromIterable(const [
        'event: token\ndata: {"content": "正在查询"}',
        'event: step\ndata: {"name": "list_containers", "arguments": {}}',
        'event: step_result\ndata: {"name": "list_containers", "result": "ok"}',
        'event: done\ndata: {}',
      ]);
    };
    await pumpChatScreen(tester);

    await tester.enterText(find.byType(TextField), '看看容器');
    await tester.pump();
    await tester.tap(find.byKey(const Key('agent_send_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 工具名出现在 chips 与步骤徽章中，共 2 处
    expect(find.text('list_containers'), findsNWidgets(2),
        reason: '步骤徽章应显示工具名');
  });

  testWidgets('工具全不选时显示默认 skill 提示', (tester) async {
    await pumpChatScreen(tester);

    // 取消全部 chips（2 skills + 1 tool）
    for (final name in [
      'docker_mirror_pull',
      'docker_pull_from_file',
      'list_containers',
    ]) {
      await tester.tap(find.byKey(Key('agent_tool_chip_$name')));
      await tester.pump();
    }

    await tester.enterText(find.byType(TextField), 'hi');
    await tester.pump();
    await tester.tap(find.byKey(const Key('agent_send_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('未选择任何工具，将使用默认 skill'), findsOneWidget,
        reason: '工具全不选时应提示将使用默认 skill');
  });
}
