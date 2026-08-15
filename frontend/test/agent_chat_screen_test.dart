import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
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
    Locale locale = const Locale('zh'),
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
      locale: locale,
    ));
    await tester.tap(find.text('open-chat'));
    await tester.pump();
    // issue #28：滑入动画 260ms，推进完整时长后再断言位置/尺寸
    await tester.pump(const Duration(milliseconds: 400));
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

  testWidgets('点击 AI 按钮后展示扩展式 AI 输入面板，并可关闭恢复导航', (tester) async {
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
    expect(find.byKey(const Key('bottom_agent_composer')), findsOneWidget,
        reason: '展开后应展示扩展式 AI 输入面板');
    expect(find.byKey(const Key('bottom_agent_close')), findsOneWidget,
        reason: '展开输入框后应提供返回导航按钮');
    expect(find.byKey(const Key('agent_chat_button')), findsNothing,
        reason: '展开状态不应保留 AI 入口按钮');
    final sendBtn = tester.widget<IconButton>(
      find.byKey(const Key('bottom_agent_send')),
    );
    expect(sendBtn.onPressed, isNull, reason: '底栏空输入时发送按钮应禁用');

    for (final label in ['快速', 'Docker 指令', '容器状态', '查看日志', '清理镜像', '更多']) {
      expect(find.text(label), findsOneWidget,
          reason: '扩展式输入面板应展示静态快捷项：$label');
    }
    expect(tester.getSize(find.byKey(const Key('bottom_agent_composer'))).height,
        greaterThan(100), reason: '扩展式输入面板应提供双行布局空间');

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
    expect(find.byType(AlertDialog), findsNothing,
        reason: '非手机端不再使用居中 dialog，改为右侧滑出右边栏（issue #28）');
    expect(find.byKey(const Key('agent_side_panel')), findsOneWidget,
        reason: '发送后聊天框应以右边栏形态展示');
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

  testWidgets('HTTP 503（LLM 未配置）弹出提示并引导配置 API', (tester) async {
    AgentService.debugSseConnector = (uri, headers, {body, ignoreSsl = false}) {
      return Stream<String>.error(Exception(
          'HTTP 503: {"error_code":"llm_not_configured",'
          '"detail":"LLM 未配置"}'));
    };
    await pumpChatScreen(tester);

    await tester.enterText(find.byType(TextField), 'hi');
    await tester.pump();
    await tester.tap(find.byKey(const Key('agent_send_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 应弹出提示（独立于聊天框对话框），仅提供 AI 供应商配置入口
    // （issue #33：外部 hermes 配置选项已删除，只调用容器内集成的 hermes）
    expect(find.byKey(const Key('llm_not_configured_dialog')), findsOneWidget,
        reason: 'LLM 未配置（503）应弹出提示');
    expect(find.text('配置 Hermes'), findsNothing,
        reason: '外部 hermes 配置入口已删除，不应再提供');
    expect(find.text('配置 AI 供应商'), findsOneWidget,
        reason: '应提供 AI 供应商配置入口');
  });

  testWidgets('503 弹窗点击「配置 AI 供应商」跳转供应商配置页', (tester) async {
    AgentService.debugSseConnector = (uri, headers, {body, ignoreSsl = false}) {
      return Stream<String>.error(Exception(
          'HTTP 503: {"error_code":"llm_not_configured",'
          '"detail":"LLM 未配置"}'));
    };
    await pumpChatScreen(tester);

    await tester.enterText(find.byType(TextField), 'hi');
    await tester.pump();
    await tester.tap(find.byKey(const Key('agent_send_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('llm_not_configured_dialog')), findsOneWidget);

    await tester.tap(find.text('配置 AI 供应商'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('AI 供应商配置'), findsOneWidget,
        reason: '点击配置 AI 供应商应跳转供应商配置页');
  });

  // ---- issue #26：输入框界面优化 + Docker 常用快捷指令 ----

  testWidgets('输入框下方显示 Docker 常用快捷指令', (tester) async {
    await pumpChatScreen(tester);

    expect(find.byKey(const Key('agent_quick_commands')), findsOneWidget,
        reason: '输入框下方应有快捷指令行');
    for (final label in ['拉取镜像', '运行容器', '配置环境变量', '查看日志', '清理镜像', '容器状态']) {
      expect(find.text(label), findsOneWidget,
          reason: '快捷指令应显示：$label');
    }
  });

  testWidgets('点击快捷指令填入输入框，发送按钮可用', (tester) async {
    AgentService.debugSseConnector = (uri, headers, {body, ignoreSsl = false}) {
      return const Stream<String>.empty();
    };
    await pumpChatScreen(tester);

    // 初始空输入：发送按钮禁用
    expect(
      tester.widget<IconButton>(find.byKey(const Key('agent_send_button'))).onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('agent_quick_chip_pull_image')));
    await tester.pump();

    final input = tester.widget<TextField>(find.byKey(const Key('agent_input_field')));
    expect(input.controller!.text, contains('nginx'),
        reason: '点击「拉取镜像」应填入完整指令');
    expect(input.controller!.text, contains('拉取'),
        reason: '填入的指令应包含拉取语义');
    final sendBtn = tester.widget<IconButton>(find.byKey(const Key('agent_send_button')));
    expect(sendBtn.onPressed, isNotNull, reason: '填入后发送按钮应可用');

    // 填入后可直接发送，消息上屏
    await tester.tap(find.byKey(const Key('agent_send_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('nginx'), findsWidgets,
        reason: '快捷指令发送后用户消息应上屏');
  });

  testWidgets('英文 locale 下快捷指令显示英文', (tester) async {
    await pumpChatScreen(tester, locale: const Locale('en'));

    expect(find.byKey(const Key('agent_quick_commands')), findsOneWidget);
    expect(find.text('Pull image'), findsOneWidget,
        reason: '英文环境快捷指令应为英文');

    await tester.tap(find.byKey(const Key('agent_quick_chip_pull_image')));
    await tester.pump();
    final input = tester.widget<TextField>(find.byKey(const Key('agent_input_field')));
    expect(input.controller!.text, contains('pull image'),
        reason: '英文环境填入的指令应为英文');
  });

  testWidgets('快捷指令行横向滚动（小屏幕不溢出）', (tester) async {
    await pumpChatScreen(tester);

    final scrollableFinder = find.byKey(const Key('agent_quick_commands'));
    expect(scrollableFinder, findsOneWidget);
    final scrollable =
        tester.widget<SingleChildScrollView>(scrollableFinder);
    expect(scrollable.scrollDirection, Axis.horizontal,
        reason: '快捷指令行应为横向滚动容器，避免窄屏溢出');
  });

  // ---- issue #26 第二轮：对话框样式对齐参考图 ----

  testWidgets('快捷指令胶囊为浅蓝底深色文字且无图标（参考图样式）', (tester) async {
    await pumpChatScreen(tester);

    final chip = tester.widget<ActionChip>(
        find.byKey(const Key('agent_quick_chip_pull_image')));
    final cs = Theme.of(
            tester.element(find.byKey(const Key('agent_quick_commands'))))
        .colorScheme;

    expect(chip.avatar, isNull, reason: '参考图快捷指令为纯文字胶囊，不应带图标');
    expect(chip.backgroundColor, cs.primaryContainer,
        reason: '快捷指令胶囊应为浅蓝底（参考图样式）');
    expect(chip.shape, isA<StadiumBorder>(),
        reason: '快捷指令胶囊应为胶囊形圆角（参考图样式）');

    final label = tester.widget<Text>(find.descendant(
      of: find.byKey(const Key('agent_quick_chip_pull_image')),
      matching: find.text('拉取镜像'),
    ));
    expect(label.style?.color, cs.onPrimaryContainer,
        reason: '快捷指令文字应为深色（浅蓝底上的对比色）');
  });

  // ---- issue #27：底部导航栏 AI 助手展开后宽度优化 ----

  testWidgets('AI 助手展开后输入条接近全宽，两边只留少量空隙', (tester) async {
    // 手机尺寸（390x844）
    tester.view.physicalSize = const Size(1170, 2532); // 390x844 @3x
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildTestApp(
      home: const MainTabScreen(),
      locale: const Locale('zh'),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const Key('agent_chat_button')));
    await tester.pump();
    // 展开动画完成（180ms），scale 回到 1 后测量位置不受变换影响
    await tester.pump(const Duration(milliseconds: 300));

    final composer = find.byKey(const Key('bottom_agent_composer'));
    expect(composer, findsOneWidget);

    // 宽度：屏幕宽 390 - 两边空隙 12*2 = 366，不再用固定 384 的导航栏宽度
    final composerWidth = tester.getSize(composer).width;
    expect(composerWidth, 366,
        reason: '展开后输入条应接近全宽（两边各留 12 空隙），不应沿用固定导航栏宽度');

    // 左右空隙：各 12，且不超出屏幕
    final leftEdge = tester.getTopLeft(composer).dx;
    final rightEdge = tester.getTopRight(composer).dx;
    expect(leftEdge, 12, reason: '左边应留少量空隙');
    expect(rightEdge, 378, reason: '右边应留少量空隙（390 - 12）');
  });

  testWidgets('窄屏下 AI 助手输入条变宽后仍不溢出屏幕', (tester) async {
    // 窄屏（360x800）：固定 384 宽 + 40 边距会溢出，动态宽度应恰好适配
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildTestApp(
      home: const MainTabScreen(),
      locale: const Locale('zh'),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const Key('agent_chat_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final composer = find.byKey(const Key('bottom_agent_composer'));
    expect(composer, findsOneWidget);

    final composerWidth = tester.getSize(composer).width;
    expect(composerWidth, 336, reason: '窄屏下输入条宽度应为 360 - 12*2 = 336');
    final leftEdge = tester.getTopLeft(composer).dx;
    final rightEdge = tester.getTopRight(composer).dx;
    expect(leftEdge, 12, reason: '左边留 12 空隙');
    expect(rightEdge, 348, reason: '右边留 12 空隙且不溢出屏幕（≤360）');
  });

  testWidgets('输入条左侧 AI 图标为圆形渐变 sparkle（参考图样式）', (tester) async {
    await pumpChatScreen(tester);

    final iconBox = tester.widget<Container>(
        find.byKey(const Key('agent_input_ai_icon')));
    final deco = iconBox.decoration! as BoxDecoration;
    expect(deco.shape, BoxShape.circle,
        reason: '参考图 AI 图标为圆形，非圆角方形');
    expect(deco.gradient, isNotNull,
        reason: 'AI 图标应为渐变底色');

    expect(
      find.descendant(
        of: find.byKey(const Key('agent_input_ai_icon')),
        matching: find.byIcon(RemixIcon.sparklingFill),
      ),
      findsOneWidget,
      reason: 'AI 图标内部应为 sparkle 图案（参考图样式）',
    );
  });

  // ---- issue #28：聊天框改为右侧滑出右边栏 ----

  testWidgets('非手机端聊天框为贴右全高的右边栏而非居中对话框', (tester) async {
    tester.view.physicalSize = const Size(3840, 2400); // 1280x800 @3x
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await pumpChatScreen(tester);

    expect(find.byType(AlertDialog), findsNothing,
        reason: '非手机端不应再弹出居中 AlertDialog');
    final panel = find.byKey(const Key('agent_side_panel'));
    expect(panel, findsOneWidget, reason: '聊天框应以右边栏形态展示');

    final rect = tester.getRect(panel);
    expect(rect.right, 1280, reason: '右边栏应贴屏幕右缘');
    expect(rect.top, 0, reason: '右边栏应从屏幕顶部开始');
    expect(rect.height, 800, reason: '右边栏应为全屏高度');
    expect(rect.width, 560, reason: '宽屏下右边栏宽度应为 560（与旧对话框同宽）');
  });

  testWidgets('右边栏从屏幕右侧滑入（动画起点在屏幕右侧外）', (tester) async {
    tester.view.physicalSize = const Size(3840, 2400); // 1280x800 @3x
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
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
    await tester.pump(); // 动画第一帧：右边栏应仍在屏幕右侧外

    final panel = find.byKey(const Key('agent_side_panel'));
    expect(panel, findsOneWidget, reason: '打开即应渲染右边栏（处于滑入动画中）');
    final startRect = tester.getRect(panel);
    expect(startRect.left, greaterThanOrEqualTo(1280),
        reason: '滑入动画起始时右边栏应在屏幕右侧外');

    await tester.pump(const Duration(milliseconds: 400));
    final endRect = tester.getRect(panel);
    expect(endRect.right, 1280, reason: '动画完成后右边栏应贴屏幕右缘');
  });

  testWidgets('输入框固定在右边栏底部（不随消息区滚动）', (tester) async {
    tester.view.physicalSize = const Size(3840, 2400); // 1280x800 @3x
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await pumpChatScreen(tester);

    final panelRect = tester.getRect(find.byKey(const Key('agent_side_panel')));
    final inputRect = tester.getRect(find.byKey(const Key('agent_input_field')));
    expect(inputRect.bottom, lessThan(panelRect.bottom),
        reason: '输入框应位于右边栏内部');
    expect(inputRect.bottom, greaterThan(panelRect.bottom - 160),
        reason: '输入框应固定在右边栏底部区域');
    expect(inputRect.center.dy, greaterThan(panelRect.center.dy),
        reason: '输入框应位于右边栏下半部（底部固定）');
  });

  testWidgets('窄屏下右边栏宽度自适应不溢出屏幕', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532); // 390x844 @3x
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await pumpChatScreen(tester);

    final rect = tester.getRect(find.byKey(const Key('agent_side_panel')));
    expect(rect.width, 366, reason: '窄屏右边栏宽度应为 390 - 24 = 366');
    expect(rect.right, 390, reason: '右边栏不应溢出屏幕');
  });

  testWidgets('点击右边栏外遮罩关闭右边栏', (tester) async {
    tester.view.physicalSize = const Size(3840, 2400); // 1280x800 @3x
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await pumpChatScreen(tester);
    expect(find.byKey(const Key('agent_side_panel')), findsOneWidget);

    // 点右边栏外的左侧遮罩区域
    await tester.tapAt(const Offset(100, 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('agent_side_panel')), findsNothing,
        reason: '点击遮罩应关闭右边栏');
  });

  testWidgets('右边栏头部关闭按钮关闭聊天框', (tester) async {
    tester.view.physicalSize = const Size(3840, 2400); // 1280x800 @3x
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await pumpChatScreen(tester);
    expect(find.byKey(const Key('agent_side_panel')), findsOneWidget);

    await tester.tap(find.byKey(const Key('agent_chat_close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('agent_side_panel')), findsNothing,
        reason: '点击头部关闭按钮应关闭右边栏');
  });

  // ---- issue #29：右边栏遮罩半透明（纯黑遮罩会让页面完全黑屏）----

  testWidgets('右边栏遮罩为半透明而非纯黑', (tester) async {
    tester.view.physicalSize = const Size(3840, 2400); // 1280x800 @3x
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await pumpChatScreen(tester);
    expect(find.byKey(const Key('agent_side_panel')), findsOneWidget);

    // 第一个 ModalBarrier 为框架默认实例（color=null），
    // 对话框遮罩是 dismissible 为 true 的那个
    final barrier = tester
        .widgetList<ModalBarrier>(find.byType(ModalBarrier))
        .firstWhere((b) => b.dismissible);
    expect(barrier.color, isNotNull, reason: '右边栏应有半透明遮罩');
    expect(barrier.color!.a, closeTo(0.6, 0.01),
        reason: '遮罩应为半透明（设计值 0.6）：alpha 传 60 会被饱和为纯黑，'
            '导致页面完全黑屏（issue #29）');
    expect(barrier.color!.r, 0, reason: '遮罩应为黑色系');
    expect(barrier.color!.g, 0, reason: '遮罩应为黑色系');
    expect(barrier.color!.b, 0, reason: '遮罩应为黑色系');
  });

  // ---- issue #34（第二轮）：聊天输入框点击后偶发失焦 + Web 端 null check 崩溃 ----
  //
  // 第一轮（onTap 同步强制聚焦）验证无效，用户反馈单击后仍马上失焦，
  // 且控制台报 `Null check operator used on a null value`（main.dart.wasm）。
  //
  // 根因：Flutter 3.35.x Web 引擎已知缺陷（flutter/flutter#178619、
  // #187461）——面板滑入动画期间 transform 每帧变化，框架每帧发送
  // TextInput.setEditableSizeAndTransform，与输入连接建立/关闭存在竞态，
  // 引擎 text_editing.dart 中 activeDomElement 的 `domElement!` 作用于
  // null 崩溃，DOM 层焦点移动失败 → 输入框失焦（同步 onTap 重聚焦时
  // Dart 层焦点可能尚未丢失或连接已损坏，无法恢复）。
  //
  // 第二轮防御（项目侧规避，引擎为预编译产物无法 patch）：
  // 1) 自动聚焦延迟到滑入/展开动画结束后（消除动画期竞态窗口）；
  // 2) 点击输入框后延迟重聚焦（在竞态动作完成后夺回焦点）；
  // 3) 焦点自愈监听：面板打开期间焦点一旦被抢走，延迟自动重新聚焦；
  // 4) onTapOutside 空实现保留（禁用桌面端点击外部收起焦点）。
  //
  // 以下测试用桌面端平台行为（Web 端即桌面端行为）验证：
  // 动画期不聚焦 / 动画后聚焦 / 失焦自愈 / 关闭不重聚焦。

  testWidgets('聊天输入框配置点击防护，面板内点击其他区域不收起焦点（issue #34）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await pumpChatScreen(tester);

      final inputField = find.byKey(const Key('agent_input_field'));
      final input = tester.widget<TextField>(inputField);
      expect(input.onTap, isNotNull,
          reason: '应配置点击完成时延迟重新聚焦，对抗点击过程中的焦点竞争');
      expect(input.onTapOutside, isNotNull,
          reason: '应禁用桌面端默认的点击外部收起焦点行为');
      final focusNode = input.focusNode!;

      await tester.tap(inputField);
      await tester.pump();
      expect(focusNode.hasFocus, isTrue, reason: '点击输入框应获得焦点');

      // 点击面板内输入框之外的区域（消息区）：桌面端默认行为会 unfocus，
      // 聊天面板输入框为常驻输入点，不应被抢走焦点
      final panelCenter =
          tester.getCenter(find.byKey(const Key('agent_chat_screen')));
      await tester.tapAt(panelCenter - const Offset(0, 160));
      await tester.pump();
      expect(focusNode.hasFocus, isTrue,
          reason: '聊天面板内点击非输入区域不应收起输入框焦点');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('面板滑入动画期间不自动聚焦，动画结束后自动聚焦（issue #34 第二轮）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
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
      await tester.pump(); // 滑入动画第一帧

      final inputField = find.byKey(const Key('agent_input_field'));
      final focusNode = tester.widget<TextField>(inputField).focusNode!;
      expect(focusNode.hasFocus, isFalse,
          reason: '滑入动画期间不应建立输入连接（避开 Web 引擎 setEditableSizeAndTransform 竞态窗口）');

      // 滑入动画 260ms + 缓冲：320ms 后应自动聚焦
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pump();
      expect(focusNode.hasFocus, isTrue,
          reason: '动画结束后应自动聚焦输入框，用户可直接输入');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('点击输入框后焦点被竞态抢走会自动重新聚焦（issue #34 自愈）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await pumpChatScreen(tester);

      final inputField = find.byKey(const Key('agent_input_field'));
      final focusNode = tester.widget<TextField>(inputField).focusNode!;
      expect(focusNode.hasFocus, isTrue, reason: '打开后输入框应已聚焦');

      // 模拟 Web 端引擎竞态：单击之后马上抢走焦点
      await tester.tap(inputField);
      await tester.pump();
      focusNode.unfocus();
      await tester.pump();
      expect(focusNode.hasFocus, isFalse, reason: '前置条件：焦点已被抢走');

      // 自愈：延迟重聚焦应在竞态动作完成后夺回焦点
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(focusNode.hasFocus, isTrue,
          reason: '焦点被抢走后应自动重新聚焦，无需长按');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('底部输入条同样具备点击防护（issue #34）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await tester.pumpWidget(buildTestApp(
        home: const MainTabScreen(),
        locale: const Locale('zh'),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      // 展开底部输入条
      await tester.tap(find.byKey(const Key('agent_chat_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final bottomInput = find.byKey(const Key('bottom_agent_input'));
      final input = tester.widget<TextField>(bottomInput);
      expect(input.onTap, isNotNull,
          reason: '底部输入条应配置点击完成时延迟重新聚焦');
      expect(input.onTapOutside, isNotNull,
          reason: '底部输入条应禁用桌面端默认的点击外部收起焦点行为');
      final focusNode = input.focusNode!;

      await tester.tap(bottomInput);
      await tester.pump();
      expect(focusNode.hasFocus, isTrue, reason: '底部输入条点击应获得焦点');

      // 点击输入条内输入框之外的区域（快捷指令行，非交互区域）：
      // 桌面端默认行为会 unfocus，输入条展开时输入框为常驻输入点，
      // 不应被抢走焦点
      await tester.tapAt(
          tester.getCenter(find.byKey(const Key('bottom_agent_quick_items'))));
      await tester.pump();
      expect(focusNode.hasFocus, isTrue,
          reason: '底部输入条内点击非输入区域不应收起输入框焦点');

      // 关闭按钮行为不受防护影响
      await tester.tap(find.byKey(const Key('bottom_agent_close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('agent_chat_button')), findsOneWidget,
          reason: '点击关闭按钮应回到导航栏');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('底部输入条展开动画期间不聚焦，动画后聚焦 + 失焦自愈 + 关闭不重聚焦（issue #34 第二轮）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await tester.pumpWidget(buildTestApp(
        home: const MainTabScreen(),
        locale: const Locale('zh'),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      // 展开底部输入条：展开缩放动画 180ms
      await tester.tap(find.byKey(const Key('agent_chat_button')));
      await tester.pump(); // 展开动画第一帧

      final bottomInput = find.byKey(const Key('bottom_agent_input'));
      final focusNode = tester.widget<TextField>(bottomInput).focusNode!;
      expect(focusNode.hasFocus, isFalse,
          reason: '展开动画期间不应建立输入连接（避开 Web 引擎竞态窗口）');

      // 动画 180ms 结束 + 缓冲：240ms 后应自动聚焦
      await tester.pump(const Duration(milliseconds: 240));
      await tester.pump();
      expect(focusNode.hasFocus, isTrue, reason: '展开动画结束后应自动聚焦');

      // 失焦自愈：模拟点击后焦点被抢走
      await tester.tap(bottomInput);
      await tester.pump();
      focusNode.unfocus();
      await tester.pump();
      expect(focusNode.hasFocus, isFalse, reason: '前置条件：焦点已被抢走');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(focusNode.hasFocus, isTrue,
          reason: '焦点被抢走后应自动重新聚焦');

      // 关闭：主动收起输入条不允许自愈干扰
      await tester.tap(find.byKey(const Key('bottom_agent_close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('agent_chat_button')), findsOneWidget,
          reason: '点击关闭按钮应回到导航栏');
      expect(focusNode.hasFocus, isFalse,
          reason: '关闭后输入条不应重新聚焦（自愈不干扰主动收起）');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
