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

  testWidgets('点击 AI 按钮弹出聊天框（VM 环境走居中 dialog）', (tester) async {
    AgentService.debugFetchToolsOverride = fakeFetchTools;
    await tester.pumpWidget(buildTestApp(
      home: const MainTabScreen(),
      locale: const Locale('zh'),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const Key('agent_chat_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AgentChatScreen), findsOneWidget,
        reason: '点击 AI 按钮应弹出聊天框');
    expect(find.byType(AlertDialog), findsOneWidget,
        reason: 'VM（非手机端）环境应使用居中 dialog');
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
}
