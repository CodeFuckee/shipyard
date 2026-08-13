import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/screens/agent_debug_log_detail_screen.dart';
import 'package:mobile_portainer_flutter_module/services/agent_service.dart';
import 'package:mobile_portainer_flutter_module/services/platform/preferences_service.dart';
import 'package:mobile_portainer_flutter_module/widgets/empty_view.dart';
import 'package:mobile_portainer_flutter_module/widgets/error_view.dart';
import 'package:mobile_portainer_flutter_module/widgets/loading_view.dart';

/// AI 调试日志列表页（issue #24）。
///
/// 展示每次 AI 对话的调试记录摘要（LLM 来源、状态、耗时），点击进入
/// 详情页查看完整执行链路；支持下拉刷新与一键清空（AlertDialog 确认）。
class AgentDebugLogsScreen extends StatefulWidget {
  const AgentDebugLogsScreen({super.key});

  @override
  State<AgentDebugLogsScreen> createState() => _AgentDebugLogsScreenState();
}

class _AgentDebugLogsScreenState extends State<AgentDebugLogsScreen> {
  List<AgentDebugLogSummary> _logs = [];
  bool _isLoading = true;
  String? _loadError;
  String? _backendError;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  /// 解析当前活动服务器（web_backend_* 优先，回退 docker_auth_*）。
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

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final backend = await _resolveBackend();
      if (backend == null) {
        if (!mounted) return;
        setState(() {
          _backendError = '未配置服务器或 API Key';
          _isLoading = false;
        });
        return;
      }
      final logs = await AgentService.fetchDebugLogs(
          baseUrl: backend.url, token: backend.token);
      if (!mounted) return;
      setState(() {
        _logs = logs;
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

  Future<void> _confirmClear() async {
    final t = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.agentDebugClearConfirmTitle),
        content: Text(t.agentDebugClearConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(t.agentDebugClear),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final backend = await _resolveBackend();
      if (backend == null) return;
      await AgentService.clearDebugLogs(
          baseUrl: backend.url, token: backend.token);
      if (!mounted) return;
      setState(() {
        _logs = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.agentDebugCleared)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.agentDebugClearFailed}：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.agentDebugTitle),
        actions: [
          IconButton(
            icon: const Icon(RemixIcon.deleteBinLine),
            tooltip: t.agentDebugClear,
            onPressed: _logs.isEmpty ? null : _confirmClear,
          ),
        ],
      ),
      body: _buildBody(context, t, colorScheme),
    );
  }

  Widget _buildBody(
      BuildContext context, AppLocalizations t, ColorScheme colorScheme) {
    if (_isLoading) {
      return const LoadingView();
    }
    if (_backendError != null) {
      return ErrorView(message: _backendError!, onRetry: _loadLogs);
    }
    if (_loadError != null) {
      return ErrorView(
        message: t.agentDebugLoadFailed,
        subtitle: _loadError,
        onRetry: _loadLogs,
      );
    }
    if (_logs.isEmpty) {
      return EmptyView(
        icon: RemixIcon.terminalBoxLine,
        message: t.agentDebugEmpty,
        actionLabel: t.agentDebugRetry,
        onAction: _loadLogs,
      );
    }
    return RefreshIndicator(
      onRefresh: _loadLogs,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _logs.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) =>
            _buildLogTile(context, _logs[index], colorScheme),
      ),
    );
  }

  Widget _buildLogTile(
      BuildContext context, AgentDebugLogSummary log, ColorScheme colorScheme) {
    return ListTile(
      leading: Icon(
        log.isSuccess ? RemixIcon.checkboxCircleLine : RemixIcon.closeCircleLine,
        color: log.isSuccess ? Colors.green : colorScheme.error,
        size: 28,
      ),
      title: Text(
        log.requestText.isEmpty ? '（无文本请求）' : log.requestText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _logSubtitle(log),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        _formatDuration(log.durationMs),
        style: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AgentDebugLogDetailScreen(logId: log.id),
          ),
        );
      },
    );
  }

  String _logSubtitle(AgentDebugLogSummary log) {
    final parts = <String>[
      if (log.llmName != null && log.llmName!.isNotEmpty) log.llmName!,
      if (log.llmModel != null && log.llmModel!.isNotEmpty) log.llmModel!,
    ];
    final source = parts.isEmpty ? (log.llmSource ?? '') : parts.join(' · ');
    final time = _formatTime(log.createdAt);
    return '$time · $source';
  }

  /// 把 ISO 时间字符串格式化为「MM-dd HH:mm」（解析失败原样返回）。
  String _formatTime(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final local = parsed.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  /// 耗时格式：<1s 显示毫秒，否则显示秒（1 位小数）。
  String _formatDuration(int ms) {
    if (ms < 1000) return '$ms ms';
    return '${(ms / 1000).toStringAsFixed(1)} s';
  }
}
