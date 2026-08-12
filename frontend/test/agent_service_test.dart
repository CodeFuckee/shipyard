import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_portainer_flutter_module/services/agent_service.dart';

/// AI agent 服务层测试：SSE 帧解析、流式对话事件序列、工具列表获取。
///
/// 覆盖：
/// - 正常路径：token/step/step_result/reply/done 事件解析、fetchTools 200 解析
/// - 边界情况：空帧跳过、非法 JSON 跳过、多行 data 拼接、无 event 行、
///   网络错误转为事件流错误、401/500 抛异常、token 为空请求头
void main() {
  group('parseSseFrame', () {
    test('解析 token 帧', () {
      final event = AgentService.parseSseFrame(
          'event: token\ndata: {"content": "你"}');
      expect(event, isNotNull);
      expect(event!.type, 'token');
      expect(event.content, '你');
    });

    test('解析 done 帧（空对象 data）', () {
      final event =
          AgentService.parseSseFrame('event: done\ndata: {}');
      expect(event!.type, 'done');
    });

    test('解析 step 帧的 arguments', () {
      final event = AgentService.parseSseFrame(
          'event: step\ndata: {"name": "list_containers", "arguments": {"summary": true}}');
      expect(event!.type, 'step');
      expect(event.name, 'list_containers');
      expect(event.arguments, {'summary': true});
    });

    test('解析 step_result 帧的 result', () {
      final event = AgentService.parseSseFrame(
          'event: step_result\ndata: {"name": "list_containers", "result": "ok"}');
      expect(event!.type, 'step_result');
      expect(event.result, 'ok');
    });

    test('多行 data 拼接为完整 JSON（标准 SSE：续行带 data: 前缀）', () {
      // JSON 允许 token 间空白（含换行），续行拼接后仍可解析
      final event = AgentService.parseSseFrame(
          'event: reply\ndata: {"content": "hello",\ndata: "extra": 1}');
      expect(event!.type, 'reply');
      expect(event.content, 'hello');
    });

    test('无 event 行的帧跳过（默认 message 类型丢弃）', () {
      expect(AgentService.parseSseFrame('data: {"x": 1}'), isNull);
    });

    test('空帧返回 null', () {
      expect(AgentService.parseSseFrame(''), isNull);
      expect(AgentService.parseSseFrame('   '), isNull);
    });

    test('非法 JSON data 返回 null（不崩溃）', () {
      final event =
          AgentService.parseSseFrame('event: token\ndata: not-json');
      expect(event, isNull);
    });
  });

  group('chatStream', () {
    tearDown(() {
      AgentService.debugSseConnector = null;
    });

    Stream<String> fakeConnector(
      Uri uri,
      Map<String, String> headers, {
      String? body,
      bool ignoreSsl = false,
    }) {
      return Stream<String>.fromIterable(const [
        'event: token\ndata: {"content": "你"}',
        'event: step\ndata: {"name": "list_containers", "arguments": {"summary": true}}',
        'event: step_result\ndata: {"name": "list_containers", "result": "[1 个容器]"}',
        'event: reply\ndata: {"content": "你好，共 1 个容器"}',
        'event: done\ndata: {}',
      ]);
    }

    test('完整事件序列', () async {
      AgentService.debugSseConnector = fakeConnector;
      final events = await AgentService.chatStream(
        baseUrl: 'https://example.com',
        token: 'test-key',
        messages: [
          {'role': 'user', 'content': '看看容器'}
        ],
        tools: const ['list_containers'],
      ).toList();

      expect(events.map((e) => e.type).toList(),
          ['token', 'step', 'step_result', 'reply', 'done']);
      expect(events[0].content, '你');
      expect(events[1].name, 'list_containers');
      expect(events[2].result, '[1 个容器]');
      expect(events[3].content, '你好，共 1 个容器');
    });

    test('请求 URL 与 body 正确（含 token 请求头）', () async {
      Uri? capturedUri;
      Map<String, String>? capturedHeaders;
      String? capturedBody;
      AgentService.debugSseConnector = (uri, headers, {body, ignoreSsl = false}) {
        capturedUri = uri;
        capturedHeaders = headers;
        capturedBody = body;
        return const Stream<String>.empty();
      };

      await AgentService.chatStream(
        baseUrl: 'https://example.com',
        token: 'test-key',
        messages: [
          {'role': 'user', 'content': 'hi'}
        ],
        tools: const ['list_containers'],
      ).toList();

      expect(capturedUri!.toString(),
          'https://example.com/admin/agent/chat/stream');
      expect(capturedHeaders!['X-API-Key'], 'test-key');
      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(body['tools'], ['list_containers']);
      expect((body['messages'] as List).length, 1);
    });

    test('JWT 风格 token 使用 Bearer 请求头', () async {
      Map<String, String>? capturedHeaders;
      AgentService.debugSseConnector = (uri, headers, {body, ignoreSsl = false}) {
        capturedHeaders = headers;
        return const Stream<String>.empty();
      };

      await AgentService.chatStream(
        baseUrl: 'https://example.com',
        token: 'eyJhbGciOiJIUzI1NiJ9.xxx.yyy',
        messages: [
          {'role': 'user', 'content': 'hi'}
        ],
        tools: const [],
      ).toList();

      expect(capturedHeaders!['Authorization'], 'Bearer eyJhbGciOiJIUzI1NiJ9.xxx.yyy');
      expect(capturedHeaders!.containsKey('X-API-Key'), isFalse);
    });

    test('连接异常转为事件流错误', () async {
      AgentService.debugSseConnector = (uri, headers, {body, ignoreSsl = false}) {
        return Stream<String>.error(Exception('网络连接失败'));
      };

      final events = <AgentChatEvent>[];
      Object? caught;
      try {
        await for (final e in AgentService.chatStream(
          baseUrl: 'https://example.com',
          token: 'test-key',
          messages: [
            {'role': 'user', 'content': 'hi'}
          ],
          tools: const [],
        )) {
          events.add(e);
        }
      } catch (e) {
        caught = e;
      }

      expect(events, isEmpty);
      expect(caught, isNotNull, reason: '连接错误应传播给调用方');
    });

    test('非法帧与空帧被跳过，不影响后续事件', () async {
      AgentService.debugSseConnector = (uri, headers, {body, ignoreSsl = false}) {
        return Stream<String>.fromIterable(const [
          '',
          'event: token\ndata: not-json',
          'event: reply\ndata: {"content": "ok"}',
          'event: done\ndata: {}',
        ]);
      };

      final events = await AgentService.chatStream(
        baseUrl: 'https://example.com',
        token: 'test-key',
        messages: [
          {'role': 'user', 'content': 'hi'}
        ],
        tools: const [],
      ).toList();

      expect(events.map((e) => e.type).toList(), ['reply', 'done']);
    });
  });

  group('fetchTools', () {
    test('200 解析 skills 与 tools', () async {
      AgentService.debugHttpClient = MockClient((request) async {
        expect(request.url.toString(),
            'https://example.com/admin/agent/tools');
        expect(request.headers['X-API-Key'], 'test-key');
        return http.Response(
          jsonEncode({
            'skills': [
              {
                'name': 'docker_mirror_pull',
                'description': '拉取单个镜像',
                'group': '镜像拉取',
              }
            ],
            'tools': [
              {
                'name': 'list_containers',
                'description': '列出所有容器',
                'group': '容器',
                'parameters': {
                  'summary': {'type': 'boolean', 'required': false}
                },
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final info = await AgentService.fetchTools(
          baseUrl: 'https://example.com', token: 'test-key');
      expect(info.skills.length, 1);
      expect(info.skills.first.name, 'docker_mirror_pull');
      expect(info.tools.length, 1);
      expect(info.tools.first.name, 'list_containers');
      expect(info.tools.first.group, '容器');
      expect(info.tools.first.parameters.containsKey('summary'), isTrue);
    });

    test('401 抛出异常', () async {
      AgentService.debugHttpClient =
          MockClient((request) async => http.Response('Unauthorized', 401));
      expect(
        () => AgentService.fetchTools(
            baseUrl: 'https://example.com', token: 'test-key'),
        throwsException,
      );
    });

    test('网络异常抛出', () async {
      AgentService.debugHttpClient =
          MockClient((request) async => throw Exception('connection refused'));
      expect(
        () => AgentService.fetchTools(
            baseUrl: 'https://example.com', token: 'test-key'),
        throwsException,
      );
    });
  });
}
