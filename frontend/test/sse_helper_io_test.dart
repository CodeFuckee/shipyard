import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_portainer_flutter_module/services/agent_service.dart';
import 'package:mobile_portainer_flutter_module/services/platform/sse_helper.dart';

/// SSE 请求链路（io 实现，VM 测试环境解析为 dart:io 版本）的真实 HTTP 行为测试。
///
/// 复现 issue #23 根因：chatStream 把 JSON 请求体编码为字符串后交给
/// SseHelper 发送，若未设置 Content-Type: application/json，dart:io 的
/// HttpClientRequest 不带 JSON 头，FastAPI 无法解析 JSON，把整个 body 当作
/// 字符串绑定给 Pydantic 模型，返回 422 model_attributes_type
/// （"Input should be a valid dictionary or object to extract fields
/// from"，loc=["body"]）。
void main() {
  test('chatStream 真实链路：POST 请求带 Content-Type: application/json', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    String? receivedContentType;
    late String receivedBody;
    server.listen((request) async {
      receivedContentType = request.headers.contentType?.mimeType;
      receivedBody = await utf8.decoder.bind(request).join();
      request.response.statusCode = 200;
      request.response.write('event: done\ndata: {}\n\n');
      await request.response.close();
    });

    // 不注入 debugSseConnector：走真实 SseHelper（io 实现）端到端链路
    final events = await AgentService.chatStream(
      baseUrl: 'http://127.0.0.1:${server.port}',
      token: 'test-key',
      messages: [
        {'role': 'user', 'content': 'hi'}
      ],
      tools: const ['list_containers'],
    ).toList();

    expect(events.map((e) => e.type).toList(), ['done']);
    expect(receivedContentType, 'application/json',
        reason: 'JSON 请求体必须带 application/json Content-Type；'
            '否则后端 FastAPI 无法解析 body，返回 422 model_attributes_type'
            '（issue #23，loc=["body"]）');
    expect(jsonDecode(receivedBody),
        isA<Map<String, dynamic>>().having((m) => m['tools'], 'tools',
            ['list_containers']));
  });

  test('非 200 响应以流错误上报（含响应体，供提取可读提示）', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      request.response.statusCode = 422;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'detail': [
          {
            'type': 'model_attributes_type',
            'loc': ['body'],
            'msg': 'Input should be a valid dictionary or object to extract fields from',
          }
        ]
      }));
      await request.response.close();
    });

    Object? caught;
    try {
      await SseHelper.connect(
        uri: Uri.parse('http://127.0.0.1:${server.port}/x'),
        headers: const {},
        body: 'not-json',
      ).toList();
    } catch (e) {
      caught = e;
    }

    expect(caught, isNotNull);
    expect(caught.toString(), contains('HTTP 422'));
    expect(caught.toString(), contains('model_attributes_type'),
        reason: '422 响应体应随流错误上报，调用方才能提取可读提示');
  });

  test('chatStream 真实链路：422 响应转为可读异常（不暴露原始 JSON）', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      request.response.statusCode = 422;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'detail': [
          {
            'type': 'model_attributes_type',
            'loc': ['body'],
            'msg': 'Input should be a valid dictionary or object to extract fields from',
          }
        ]
      }));
      await request.response.close();
    });

    Object? caught;
    try {
      await AgentService.chatStream(
        baseUrl: 'http://127.0.0.1:${server.port}',
        token: 'test-key',
        messages: [
          {'role': 'user', 'content': 'hi'}
        ],
        tools: const ['list_containers'],
      ).toList();
    } catch (e) {
      caught = e;
    }

    expect(caught, isA<AgentChatHttpException>());
    expect(caught.toString(), '请求格式错误（HTTP 422）');
    expect(caught.toString(), isNot(contains('model_attributes_type')),
        reason: '后端原始错误 JSON 不应暴露给用户');
  });
}
