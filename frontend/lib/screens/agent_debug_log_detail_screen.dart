import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/services/agent_service.dart';
import 'package:mobile_portainer_flutter_module/services/platform/preferences_service.dart';
import 'package:mobile_portainer_flutter_module/widgets/error_view.dart';
import 'package:mobile_portainer_flutter_module/widgets/loading_view.dart';

/// AI 调试日志详情页（issue #24）。
///
/// 展示单次对话的完整调试链路：
/// - 概览卡：LLM 来源 / 模型 / 状态 / 耗时 / 启用工具
/// - 错误信息（失败时）
/// - 执行链路：步骤与工具调用事件（流式 step/step_result 或非流式 role 步骤）
/// - 对话内容：完整请求消息与最终回复
class AgentDebugLogDetailScreen extends StatefulWidget {
  final String logId;

  const AgentDebugLogDetailScreen({super.key, required this.logId});

  @override
  State<AgentDebugLogDetailScreen> createState() =>
      _AgentDebugLogDetailScreenState();
}

class _AgentDebugLogDetailScreenState extends State<AgentDebugLogDetailScreen> {
  AgentDebugLogDetail? _detail;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<({String url, String token})?> _resolveBackend() async {
    final prefs = await PreferencesService.getInstance();
    var url = prefs.getString('web_backend_url');
    var token = prefs.getString('web_backend_token');
    if (url == null || url.isEmpty) {
      url = prefs.getString('docker_auth_server_url');
      token = prefs.getString('docker_auth_token');
    }
    if (url == null || url.isEmpty) return null;
    token ??= prefs.getString('docker_api_key');
    if (token == null || token.isEmpty) return null;
    return (url: url, token: token);
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final backend = await _resolveBackend();
      if (backend == null) {
        if (!mounted) return;
        setState(() {
          _loadError = '未配置服务器或 API Key';
          _isLoading = false;
        });
        return;
      }
      final detail = await AgentService.fetchDebugLogDetail(
          baseUrl: backend.url, token: backend.token, id: widget.logId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t.agentDebugDetailTitle)),
      body: _buildBody(context, t, colorScheme),
    );
  }

  Widget _buildBody(
      BuildContext context, AppLocalizations t, ColorScheme colorScheme) {
    if (_isLoading) {
      return const LoadingView();
    }
    final detail = _detail;
    if (_loadError != null || detail == null) {
      return ErrorView(
        message: t.agentDebugLoadFailed,
        subtitle: _loadError,
        onRetry: _loadDetail,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildOverviewCard(t, detail, colorScheme),
        if (!detail.summary.isSuccess && detail.errorMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildErrorCard(t, detail.errorMessage, colorScheme),
        ],
        if (detail.events.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildSectionTitle(t.agentDebugSteps),
          ...detail.events.map((e) => _buildEventTile(t, e, colorScheme)),
        ],
        if (detail.messages.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildSectionTitle(t.agentDebugConversation),
          ...detail.messages.map((m) => _buildMessageTile(t, m, colorScheme)),
        ],
        if (detail.reply.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildSectionTitle(t.agentDebugReply),
          _buildTextCard(detail.reply, colorScheme),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildOverviewCard(
      AppLocalizations t, AgentDebugLogDetail detail, ColorScheme colorScheme) {
    final summary = detail.summary;
    final source = summary.llmSource == 'provider' ? t.agentDebugSourceProvider : summary.llmSource ?? '';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  summary.isSuccess
                      ? RemixIcon.checkboxCircleLine
                      : RemixIcon.closeCircleLine,
                  color: summary.isSuccess ? Colors.green : colorScheme.error,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(
                  summary.isSuccess
                      ? t.agentDebugStatusSuccess
                      : t.agentDebugStatusError,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  _formatDuration(summary.durationMs),
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _overviewRow(t.agentDebugSource, summary.llmName ?? source),
            _overviewRow(t.agentDebugModel, summary.llmModel ?? '—'),
            _overviewRow(
              t.agentDebugTools,
              detail.toolsNames.isEmpty ? '—' : detail.toolsNames.join('、'),
            ),
            _overviewRow(t.agentDebugTime, _formatDateTime(summary.createdAt)),
          ],
        ),
      ),
    );
  }

  Widget _overviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(
      AppLocalizations t, String message, ColorScheme colorScheme) {
    return Card(
      margin: EdgeInsets.zero,
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.agentDebugError,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              message,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    );
  }

  Widget _buildTextCard(String text, ColorScheme colorScheme) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SelectableText(text, style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  /// 执行链路事件：流式 step/step_result（含 type 键）或非流式步骤（含 role 键）。
  Widget _buildEventTile(
      AppLocalizations t, Map<String, dynamic> event, ColorScheme colorScheme) {
    final type = event['type'] as String?;
    if (type == 'step') {
      // 工具调用开始：名称 + 参数
      final name = event['name'] as String? ?? '';
      final arguments = event['arguments'];
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          dense: true,
          leading: Icon(RemixIcon.toolsLine, color: colorScheme.primary),
          title: Text(t.agentDebugToolCallName(name),
              style: const TextStyle(fontSize: 13)),
          subtitle: Text(
            _formatJson(arguments),
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    if (type == 'step_result') {
      // 工具调用结束：名称 + 结果
      final name = event['name'] as String? ?? '';
      final result = event['result'];
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          dense: true,
          leading: Icon(RemixIcon.checkDoubleLine, color: Colors.green),
          title: Text(t.agentDebugToolResultName(name),
              style: const TextStyle(fontSize: 13)),
          subtitle: Text(
            _formatJson(result),
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    // 非流式步骤：role=ai/tool 的消息
    final role = event['role'] as String? ?? '';
    final content = event['content'] as String? ?? '';
    final isTool = role == 'tool';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: Icon(
          isTool ? RemixIcon.checkDoubleLine : RemixIcon.robotLine,
          color: isTool ? Colors.green : colorScheme.primary,
        ),
        title: Text(
          isTool ? t.agentDebugAgentStep : t.agentDebugToolStep,
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          content,
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// 对话内容：请求消息（user / assistant / tool 角色）。
  Widget _buildMessageTile(
      AppLocalizations t, Map<String, dynamic> message, ColorScheme colorScheme) {
    final role = message['role'] as String? ?? '';
    final content = message['content'] as String? ?? '';
    final roleLabel = switch (role) {
      'user' => t.agentChatYou,
      'assistant' => t.agentDebugAssistant,
      'tool' => t.agentDebugToolRole,
      'system' => t.agentDebugSystemRole,
      _ => role,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              roleLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(content, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  /// JSON 参数格式化：对象/数组缩进展示，字符串原样。
  String _formatJson(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(value);
  }

  String _formatDuration(int ms) {
    if (ms < 1000) return '$ms ms';
    return '${(ms / 1000).toStringAsFixed(1)} s';
  }

  String _formatDateTime(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final local = parsed.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}
