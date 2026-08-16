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

/// AI agent 对话会话摘要（GET /admin/agent/chat-sessions 返回项，issue #38）。
///
/// 每次成功对话保存/更新为一条会话；标题自动取首条用户消息摘要；
/// updatedAt 为最近一次对话时间（列表按此倒序，最新在前）。
class AgentChatSession {
  final int id;
  final String title; // 首条用户消息摘要（无用户消息时为「新会话」）
  final String? updatedAt; // ISO8601 时间字符串

  const AgentChatSession({
    required this.id,
    required this.title,
    this.updatedAt,
  });

  factory AgentChatSession.fromJson(Map<String, dynamic> json) {
    return AgentChatSession(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      updatedAt: json['updated_at'] as String?,
    );
  }
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
  final int? sessionId; // session_id 事件携带的会话 id（issue #38）

  const AgentChatEvent({
    required this.type,
    this.content = '',
    this.name = '',
    this.result = '',
    this.arguments,
    this.message = '',
    this.sessionId,
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
      sessionId: data['session_id'] as int?,
    );
  }
}

/// AI agent 调试日志摘要（GET /admin/agent/debug-logs 返回项，issue #24）。
///
/// 每次对话（流式与非流式）后端都会落库一条记录，列表只含摘要字段。
class AgentDebugLogSummary {
  final String id;
  final String createdAt;
  final String requestText; // 最后一条用户消息
  final String? llmSource; // hermes | provider
  final String? llmName;
  final String? llmModel;
  final String status; // success | error
  final int durationMs;

  const AgentDebugLogSummary({
    required this.id,
    required this.createdAt,
    required this.requestText,
    this.llmSource,
    this.llmName,
    this.llmModel,
    required this.status,
    required this.durationMs,
  });

  bool get isSuccess => status == 'success';

  factory AgentDebugLogSummary.fromJson(Map<String, dynamic> json) {
    return AgentDebugLogSummary(
      id: json['id'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      requestText: json['request_text'] as String? ?? '',
      llmSource: json['llm_source'] as String?,
      llmName: json['llm_name'] as String?,
      llmModel: json['llm_model'] as String?,
      status: json['status'] as String? ?? 'success',
      durationMs: json['duration_ms'] as int? ?? 0,
    );
  }
}

/// AI agent 调试日志详情（GET /admin/agent/debug-logs/{id}，issue #24）。
///
/// 摘要字段 + 完整请求消息（对话情况）、步骤/工具调用事件序列与最终回复。
class AgentDebugLogDetail {
  final AgentDebugLogSummary summary;
  final List<String> toolsNames;
  final String errorMessage;
  final List<Map<String, dynamic>> messages; // 完整请求消息
  final List<Map<String, dynamic>> events; // 步骤/工具调用事件序列
  final String reply; // 最终回复全文

  const AgentDebugLogDetail({
    required this.summary,
    required this.toolsNames,
    required this.errorMessage,
    required this.messages,
    required this.events,
    required this.reply,
  });

  factory AgentDebugLogDetail.fromJson(Map<String, dynamic> json) {
    return AgentDebugLogDetail(
      summary: AgentDebugLogSummary.fromJson(json),
      toolsNames: (json['tools_names'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      errorMessage: json['error_message'] as String? ?? '',
      messages: (json['messages'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(),
      events: (json['events'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(),
      reply: json['reply'] as String? ?? '',
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

/// HTTP 错误专用异常：携带状态码与可读消息（不含后端原始响应体）。
///
/// chatStream 的非 200 响应由 SseHelper 以流错误上报（含原始响应体），
/// 服务层提取 FastAPI detail 转为该类后抛出，页面据此提示用户。
class AgentChatHttpException implements Exception {
  final int statusCode;
  final String message;

  /// 后端结构化错误码（如 llm_not_configured），无错误码时为 null。
  ///
  /// 页面据此做引导提示（如弹出提示并跳转配置页），而不是只显示文案。
  final String? errorCode;

  const AgentChatHttpException(this.statusCode, this.message, {this.errorCode});

  @override
  String toString() => message;
}

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

  /// 拉取调试日志列表（GET /admin/agent/debug-logs），最新在前（issue #24）。
  static Future<List<AgentDebugLogSummary>> fetchDebugLogs({
    required String baseUrl,
    required String token,
  }) async {
    final client = debugHttpClient ?? http.Client();
    try {
      final response = await client.get(
        Uri.parse('${_cleanBaseUrl(baseUrl)}/admin/agent/debug-logs'),
        headers: _authHeaders(token),
      );
      if (response.statusCode != 200) {
        throw Exception('获取调试日志失败（HTTP ${response.statusCode}）');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final map = data is Map<String, dynamic> ? data : const <String, dynamic>{};
      return (map['logs'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AgentDebugLogSummary.fromJson)
          .toList();
    } finally {
      if (debugHttpClient == null) {
        client.close();
      }
    }
  }

  /// 拉取单条调试日志详情（GET /admin/agent/debug-logs/{id}，issue #24）。
  static Future<AgentDebugLogDetail> fetchDebugLogDetail({
    required String baseUrl,
    required String token,
    required String id,
  }) async {
    final client = debugHttpClient ?? http.Client();
    try {
      final response = await client.get(
        Uri.parse(
            '${_cleanBaseUrl(baseUrl)}/admin/agent/debug-logs/$id'),
        headers: _authHeaders(token),
      );
      if (response.statusCode != 200) {
        throw Exception('获取调试日志详情失败（HTTP ${response.statusCode}）');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final map = data is Map<String, dynamic> ? data : const <String, dynamic>{};
      return AgentDebugLogDetail.fromJson(map);
    } finally {
      if (debugHttpClient == null) {
        client.close();
      }
    }
  }

  /// 清空全部调试日志（DELETE /admin/agent/debug-logs），返回删除条数。
  static Future<int> clearDebugLogs({
    required String baseUrl,
    required String token,
  }) async {
    final client = debugHttpClient ?? http.Client();
    try {
      final response = await client.delete(
        Uri.parse('${_cleanBaseUrl(baseUrl)}/admin/agent/debug-logs'),
        headers: _authHeaders(token),
      );
      if (response.statusCode != 200) {
        throw Exception('清空调试日志失败（HTTP ${response.statusCode}）');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final map = data is Map<String, dynamic> ? data : const <String, dynamic>{};
      return map['deleted'] as int? ?? 0;
    } finally {
      if (debugHttpClient == null) {
        client.close();
      }
    }
  }

  /// 拉取对话历史（GET /admin/agent/chat-history，issue #32）。
  ///
  /// 返回后端保存的完整消息列表（role/content/steps 原始 JSON），
  /// 由聊天页面转换为 [AgentChatMessage] 恢复展示；无历史时返回空列表。
  static Future<List<Map<String, dynamic>>> fetchChatHistory({
    required String baseUrl,
    required String token,
  }) async {
    final client = debugHttpClient ?? http.Client();
    try {
      final response = await client.get(
        Uri.parse('${_cleanBaseUrl(baseUrl)}/admin/agent/chat-history'),
        headers: _authHeaders(token),
      );
      if (response.statusCode != 200) {
        throw Exception('获取对话历史失败（HTTP ${response.statusCode}）');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final map = data is Map<String, dynamic> ? data : const <String, dynamic>{};
      return (map['messages'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
    } finally {
      if (debugHttpClient == null) {
        client.close();
      }
    }
  }

  /// 清空对话历史（DELETE /admin/agent/chat-history，issue #32），
  /// 返回删除条数（空表幂等返回 0）。
  static Future<int> clearChatHistory({
    required String baseUrl,
    required String token,
  }) async {
    final client = debugHttpClient ?? http.Client();
    try {
      final response = await client.delete(
        Uri.parse('${_cleanBaseUrl(baseUrl)}/admin/agent/chat-history'),
        headers: _authHeaders(token),
      );
      if (response.statusCode != 200) {
        throw Exception('清空对话历史失败（HTTP ${response.statusCode}）');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final map = data is Map<String, dynamic> ? data : const <String, dynamic>{};
      return map['deleted'] as int? ?? 0;
    } finally {
      if (debugHttpClient == null) {
        client.close();
      }
    }
  }

  /// 拉取历史会话列表（GET /admin/agent/chat-sessions，issue #38）。
  ///
  /// 返回全部会话摘要（id/title/updated_at），最新在前；用于聊天窗口
  /// 头部「历史」按钮的显隐判断与右侧栏历史列表展示。
  static Future<List<AgentChatSession>> fetchChatSessions({
    required String baseUrl,
    required String token,
  }) async {
    final client = debugHttpClient ?? http.Client();
    try {
      final response = await client.get(
        Uri.parse('${_cleanBaseUrl(baseUrl)}/admin/agent/chat-sessions'),
        headers: _authHeaders(token),
      );
      if (response.statusCode != 200) {
        throw Exception('获取历史会话失败（HTTP ${response.statusCode}）');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final map = data is Map<String, dynamic> ? data : const <String, dynamic>{};
      return (map['sessions'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AgentChatSession.fromJson)
          .toList();
    } finally {
      if (debugHttpClient == null) {
        client.close();
      }
    }
  }

  /// 拉取单条会话完整消息（GET /admin/agent/chat-sessions/{id}，issue #38）。
  ///
  /// 消息格式与 fetchChatHistory 一致（role/content/steps），供前端
  /// 点击历史列表项后恢复该会话并可继续追问。
  static Future<List<Map<String, dynamic>>> fetchChatSessionMessages({
    required String baseUrl,
    required String token,
    required int sessionId,
  }) async {
    final client = debugHttpClient ?? http.Client();
    try {
      final response = await client.get(
        Uri.parse(
            '${_cleanBaseUrl(baseUrl)}/admin/agent/chat-sessions/$sessionId'),
        headers: _authHeaders(token),
      );
      if (response.statusCode != 200) {
        throw Exception('获取会话详情失败（HTTP ${response.statusCode}）');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final map = data is Map<String, dynamic> ? data : const <String, dynamic>{};
      return (map['messages'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
    } finally {
      if (debugHttpClient == null) {
        client.close();
      }
    }
  }

  /// 新建历史会话（POST /admin/agent/chat-sessions，issue #38）。
  ///
  /// 供「打开新会话」前把尚未落库的当前对话快照保存为一条历史会话
  /// （reply 为空时仅保存用户与助手消息，不追加空占位）。返回新建
  /// 会话摘要（含 id）。
  static Future<AgentChatSession> createChatSession({
    required String baseUrl,
    required String token,
    required List<Map<String, String>> messages,
    String reply = '',
    List<Map<String, dynamic>> events = const [],
  }) async {
    final client = debugHttpClient ?? http.Client();
    try {
      final response = await client.post(
        Uri.parse('${_cleanBaseUrl(baseUrl)}/admin/agent/chat-sessions'),
        headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
        body: jsonEncode({
          'messages': messages,
          'reply': reply,
          'events': events,
        }),
      );
      if (response.statusCode != 200) {
        throw Exception('保存历史会话失败（HTTP ${response.statusCode}）');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return AgentChatSession.fromJson(
          data is Map<String, dynamic> ? data : const <String, dynamic>{});
    } finally {
      if (debugHttpClient == null) {
        client.close();
      }
    }
  }

  /// 更新历史会话（PUT /admin/agent/chat-sessions/{id}，issue #38）。
  ///
  /// 供对话中途保存当前会话消息（标题保持首次创建时的摘要）。
  static Future<AgentChatSession> updateChatSession({
    required String baseUrl,
    required String token,
    required int sessionId,
    required List<Map<String, String>> messages,
    String reply = '',
    List<Map<String, dynamic>> events = const [],
  }) async {
    final client = debugHttpClient ?? http.Client();
    try {
      final response = await client.put(
        Uri.parse(
            '${_cleanBaseUrl(baseUrl)}/admin/agent/chat-sessions/$sessionId'),
        headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
        body: jsonEncode({
          'messages': messages,
          'reply': reply,
          'events': events,
        }),
      );
      if (response.statusCode != 200) {
        throw Exception('更新历史会话失败（HTTP ${response.statusCode}）');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return AgentChatSession.fromJson(
          data is Map<String, dynamic> ? data : const <String, dynamic>{});
    } finally {
      if (debugHttpClient == null) {
        client.close();
      }
    }
  }

  /// 删除单条历史会话（DELETE /admin/agent/chat-sessions/{id}，issue #38）。
  static Future<void> deleteChatSession({
    required String baseUrl,
    required String token,
    required int sessionId,
  }) async {
    final client = debugHttpClient ?? http.Client();
    try {
      final response = await client.delete(
        Uri.parse(
            '${_cleanBaseUrl(baseUrl)}/admin/agent/chat-sessions/$sessionId'),
        headers: _authHeaders(token),
      );
      if (response.statusCode != 200) {
        throw Exception('删除历史会话失败（HTTP ${response.statusCode}）');
      }
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
    int? sessionId,
  }) {
    final uri = Uri.parse(
        '${_cleanBaseUrl(baseUrl)}/admin/agent/chat/stream');
    final body = jsonEncode({
      'messages': messages,
      // tools 为空时省略字段（后端回退默认 skill），避免空数组被 422 拒绝
      if (tools.isNotEmpty) 'tools': tools,
      if (maxIterations != null) 'max_iterations': maxIterations,
      // issue #38：携带会话 id 时后端更新该会话，否则新建会话
      if (sessionId != null) 'session_id': sessionId,
    });
    final connector = debugSseConnector ?? _sseConnect;
    return connector(
      uri,
      {
        ..._authHeaders(token),
        // 后端 FastAPI 依赖该头解析 JSON body；缺失时把整个 body 当作
        // 字符串绑定给 Pydantic 模型，返回 422 model_attributes_type（issue #23）
        'Content-Type': 'application/json',
      },
      body: body,
      ignoreSsl: false,
    ).handleError((Object e) {
      // 把 SseHelper 上报的 HTTP 错误（含原始响应体）转为可读异常
      throw _friendlyHttpError(e);
    }).expand((frame) {
      final event = parseSseFrame(frame);
      return event == null ? const <AgentChatEvent>[] : [event];
    });
  }

  /// 把连接器流错误转为可读异常：提取 FastAPI 响应的 status、error_code 与
  /// detail，不把后端原始 JSON 暴露给用户（页面直接展示 message）。
  static Exception _friendlyHttpError(Object error) {
    final text = error.toString();
    final match = RegExp(r'HTTP (\d{3}): (.*)', dotAll: true).firstMatch(text);
    if (match == null) {
      // 非 HTTP 错误（网络异常等）：原样传播
      return error is Exception ? error : Exception(text);
    }
    final status = int.parse(match.group(1)!);
    final rawBody = match.group(2)!.trim();
    var message = 'HTTP $status';
    String? errorCode;
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        final code = decoded['error_code'];
        if (code is String && code.isNotEmpty) {
          errorCode = code; // 后端结构化错误码（issue #23）
        }
        if (status == 422 && detail is List && detail.isNotEmpty) {
          // FastAPI/Pydantic 校验错误：统一为可读提示
          message = '请求格式错误（HTTP 422）';
        } else if (detail is String && detail.isNotEmpty) {
          message = detail; // FastAPI HTTPException 的中文 detail
        }
      }
    } catch (_) {
      // 响应体非 JSON：回退状态码 + 原文首行
      final firstLine = rawBody.split('\n').first.trim();
      message = firstLine.isEmpty ? 'HTTP $status' : 'HTTP $status：$firstLine';
    }
    return AgentChatHttpException(status, message, errorCode: errorCode);
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
