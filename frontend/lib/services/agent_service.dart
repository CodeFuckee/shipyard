import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'platform/sse_helper.dart';

/// 后端 agent 工具元信息（GET /admin/agent/tools 返回项）。
///
/// 分为两类：skills（backend/skills 下的镜像拉取 skill）与
/// tools（后端 MCP server 的 33 个 Docker 管理工具）。
class AgentToolMeta {
  final String name;
  final String description;
  final String group;
  final Map<String, dynamic> parameters;

  const AgentToolMeta({
    required this.name,
    required this.description,
    required this.group,
    required this.parameters,
  });

  factory AgentToolMeta.fromJson(Map<String, dynamic> json) {
    return AgentToolMeta(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      group: json['group'] as String? ?? '',
      parameters: (json['parameters'] as Map<String, dynamic>?) ?? const {},
    );
  }
}

/// 工具列表：skills + MCP tools。
class AgentToolsInfo {
  final List<AgentToolMeta> skills;
  final List<AgentToolMeta> tools;

  const AgentToolsInfo({required this.skills, required this.tools});

  /// 全部可选工具（skills 与 tools 合并，用于选择器）。
  List<AgentToolMeta> get all => [...skills, ...tools];
}

/// AI agent 聊天事件（POST /admin/agent/chat/stream 的 SSE 事件）。
///
/// 事件类型：token（回复增量）/ step（工具调用开始）/ step_result（工具结果）
/// / reply（最终完整回复）/ done（正常结束）/ error（错误）。
class AgentChatEvent {
  final String type;
  final String content; // token / reply / error 的消息内容
  final String name; // step / step_result 的工具名
  final String result; // step_result 的工具执行结果
  final Map<String, dynamic>? arguments; // step 的工具参数
  final String message; // error 的错误描述

  const AgentChatEvent({
    required this.type,
    this.content = '',
    this.name = '',
    this.result = '',
    this.arguments,
    this.message = '',
  });

  bool get isError => type == 'error';

  factory AgentChatEvent.fromSse(String type, Map<String, dynamic> data) {
    return AgentChatEvent(
      type: type,
      content: data['content'] as String? ?? '',
      name: data['name'] as String? ?? '',
      result: data['result'] as String? ?? '',
      arguments: (data['arguments'] as Map<String, dynamic>?) ?? const {},
      message: data['message'] as String? ?? '',
    );
  }
}

/// SSE 连接器签名：发起请求并返回帧字符串流。
typedef SseConnector = Stream<String> Function(
  Uri uri,
  Map<String, String> headers, {
  String? body,
  bool ignoreSsl,
});

/// AI agent 服务：调用后端 /admin/agent/* 接口。
///
/// - [fetchTools]：拉取可用工具列表（skills + MCP tools）
/// - [chatStream]：流式对话（SSE），返回事件流
///
/// 测试注入：与 [AuthService] 相同的模式，[debugHttpClient] /
/// [debugSseConnector] / [debugFetchToolsOverride] 仅在测试中使用。
class AgentService {
  /// 测试注入的 http client（fetchTools 使用）。
  static http.Client? debugHttpClient;

  /// 测试注入的工具列表加载（跳过真实网络）。
  static Future<AgentToolsInfo> Function()? debugFetchToolsOverride;

  /// 测试注入的 SSE 连接器（chatStream 使用）。
  static SseConnector? debugSseConnector;

  /// 默认 SSE 连接器：适配平台 SseHelper 的命名参数签名。
  static Stream<String> _sseConnect(
    Uri uri,
    Map<String, String> headers, {
    String? body,
    bool ignoreSsl = false,
  }) {
    return SseHelper.connect(
        uri: uri, headers: headers, body: body, ignoreSsl: ignoreSsl);
  }

  static String _cleanBaseUrl(String url) {
    final trimmed = url.trim();
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  /// 认证请求头：JWT 风格 token 用 Bearer，其余用 X-API-Key。
  static Map<String, String> _authHeaders(String token) {
    if (token.startsWith('eyJ')) {
      return {'Authorization': 'Bearer $token'};
    }
    return {'X-API-Key': token};
  }

  /// 拉取可用工具列表（GET /admin/agent/tools）。
  static Future<AgentToolsInfo> fetchTools({
    required String baseUrl,
    required String token,
  }) async {
    if (debugFetchToolsOverride != null) {
      return debugFetchToolsOverride!();
    }
    final client = debugHttpClient ?? http.Client();
    try {
      final response = await client.get(
        Uri.parse('${_cleanBaseUrl(baseUrl)}/admin/agent/tools'),
        headers: _authHeaders(token),
      );
      if (response.statusCode != 200) {
        throw Exception('获取工具列表失败（HTTP ${response.statusCode}）');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final map = data is Map<String, dynamic> ? data : const <String, dynamic>{};
      return AgentToolsInfo(
        skills: (map['skills'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AgentToolMeta.fromJson)
            .toList(),
        tools: (map['tools'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AgentToolMeta.fromJson)
            .toList(),
      );
    } finally {
      if (debugHttpClient == null) {
        client.close();
      }
    }
  }

  /// 流式对话（POST /admin/agent/chat/stream），返回 SSE 事件流。
  ///
  /// 非法/空帧自动跳过；连接异常以流错误上报（由调用方展示）。
  static Stream<AgentChatEvent> chatStream({
    required String baseUrl,
    required String token,
    required List<Map<String, String>> messages,
    required List<String> tools,
    int? maxIterations,
  }) {
    final uri = Uri.parse(
        '${_cleanBaseUrl(baseUrl)}/admin/agent/chat/stream');
    final body = jsonEncode({
      'messages': messages,
      // tools 为空时省略字段（后端回退默认 skill），避免空数组被 422 拒绝
      if (tools.isNotEmpty) 'tools': tools,
      if (maxIterations != null) 'max_iterations': maxIterations,
    });
    final connector = debugSseConnector ?? _sseConnect;
    return connector(
      uri,
      _authHeaders(token),
      body: body,
      ignoreSsl: false,
    ).expand((frame) {
      final event = parseSseFrame(frame);
      return event == null ? const <AgentChatEvent>[] : [event];
    });
  }

  /// 解析单条 SSE 帧为事件；无 event 行、非法 JSON 时返回 null（跳过）。
  @visibleForTesting
  static AgentChatEvent? parseSseFrame(String frame) {
    String? eventType;
    final dataLines = <String>[];
    for (final line in frame.split('\n')) {
      if (line.startsWith('event:')) {
        eventType = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
    if (eventType == null || eventType.isEmpty) return null;

    Map<String, dynamic> payload = const {};
    final data = dataLines.join('\n');
    if (data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) {
          payload = decoded;
        }
      } catch (_) {
        return null; // 非法 JSON：跳过该帧，不中断整个流
      }
    }
    return AgentChatEvent.fromSse(eventType, payload);
  }
}
