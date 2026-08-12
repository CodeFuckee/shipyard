import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/services/agent_service.dart';
import 'package:mobile_portainer_flutter_module/services/platform/preferences_service.dart';
import 'package:mobile_portainer_flutter_module/utils/platform_detector.dart';

/// AI agent 聊天框（issue #21）。
///
/// 入口 [AgentChatDialog.show]：按项目对话框规则分端弹出——
/// 手机端（Android/iOS/鸿蒙）showModalBottomSheet 底部弹出；
/// Web/桌面等非手机端 showDialog 居中对话框。
///
/// 功能：发送 prompt、选择 skill（默认 backend/skills 两个）与
/// tools（后端 MCP server 的 Docker 管理工具），经后端
/// /admin/agent/chat/stream（SSE）流式对话，token 增量渲染。
class AgentChatDialog {
  static void show(BuildContext context) {
    final isMobile = PlatformDetector.isAndroid ||
        PlatformDetector.isIOS ||
        PlatformDetector.isOhos;
    if (isMobile) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => FractionallySizedBox(
          heightFactor: 0.85,
          child: const AgentChatScreen(),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          contentPadding: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: const SizedBox(
            width: 540,
            height: 660,
            child: AgentChatScreen(),
          ),
        ),
      );
    }
  }
}

/// 聊天消息（用户或助手）。
class AgentChatMessage {
  final String role; // user / assistant
  final String content;
  final List<AgentChatEvent> steps; // 助手消息关联的工具执行步骤

  const AgentChatMessage({
    required this.role,
    required this.content,
    this.steps = const [],
  });
}

class AgentChatScreen extends StatefulWidget {
  const AgentChatScreen({super.key});

  @override
  State<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends State<AgentChatScreen> {
  final TextEditingController _inputController = TextEditingController();

  final List<AgentChatMessage> _messages = [];
  AgentToolsInfo? _toolsInfo;
  String? _toolsError;
  Set<String> _selectedSkills = {};
  Set<String> _selectedTools = {};
  bool _sending = false;
  StreamSubscription<AgentChatEvent>? _subscription;

  // 当前正在生成的助手消息索引（流式 token 追加目标）
  int? _activeAssistantIndex;

  @override
  void initState() {
    super.initState();
    _loadTools();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _inputController.dispose();
    super.dispose();
  }

  /// 解析后端地址：登录服务器（web_backend_*）优先，
  /// 回退当前活动服务器（docker_auth_* / docker_api_*）。
  Future<({String url, String token})?> _resolveBackend() async {
    final prefs = await PreferencesService.getInstance();
    // getString 为同步接口（SharedPreferences / HarmonyosPreferences 均同步）
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

  Future<void> _loadTools() async {
    setState(() {
      _toolsError = null;
    });
    try {
      final backend = await _resolveBackend();
      if (backend == null) {
        if (mounted) {
          setState(() {
            _toolsError = '未登录或后端不可用';
          });
        }
        return;
      }
      final info = await AgentService.fetchTools(
          baseUrl: backend.url, token: backend.token);
      if (!mounted) return;
      setState(() {
        _toolsInfo = info;
        // skills 默认全选；tools 默认全选
        _selectedSkills = info.skills.map((s) => s.name).toSet();
        _selectedTools = info.tools.map((t) => t.name).toSet();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _toolsError = e.toString();
        });
      }
    }
  }

  void _toggleSelection(Set<String> selection, String name) {
    setState(() {
      if (!selection.add(name)) {
        selection.remove(name);
      }
    });
  }

  void _send() {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    final t = AppLocalizations.of(context)!;
    final selectedTools = {..._selectedSkills, ..._selectedTools};

    setState(() {
      _messages.add(AgentChatMessage(role: 'user', content: text));
      _messages.add(AgentChatMessage(role: 'assistant', content: ''));
      _activeAssistantIndex = _messages.length - 1;
      _sending = true;
      _inputController.clear();
    });

    final conversation = _messages
        .where((m) => m.role == 'user' || (m.role == 'assistant' && m.content.isNotEmpty))
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    unawaited(_streamChat(t, conversation, selectedTools));
  }

  Future<void> _streamChat(
    AppLocalizations t,
    List<Map<String, String>> conversation,
    Set<String> selectedTools,
  ) async {
    final backend = await _resolveBackend();
    if (backend == null) {
      _finishSending(error: t.agentChatNetworkError('后端地址不可用'));
      return;
    }

    // 工具全不选时省略 tools 字段（后端回退默认 skill）
    final tools = selectedTools.isEmpty ? const <String>[] : selectedTools.toList();

    final stream = AgentService.chatStream(
      baseUrl: backend.url,
      token: backend.token,
      messages: conversation,
      tools: tools,
    );

    _subscription = stream.listen(
      (event) {
        if (!mounted) return;
        if (event.isError) {
          _finishSending(error: event.message);
          return;
        }
        setState(() {
          final idx = _activeAssistantIndex;
          if (idx == null || idx >= _messages.length) return;
          final msg = _messages[idx];
          switch (event.type) {
            case 'token':
              _messages[idx] = AgentChatMessage(
                role: 'assistant',
                content: msg.content + event.content,
                steps: msg.steps,
              );
            case 'step':
              _messages[idx] = AgentChatMessage(
                role: 'assistant',
                content: msg.content,
                steps: [
                  ...msg.steps,
                  AgentChatEvent(
                      type: 'step',
                      name: event.name,
                      arguments: event.arguments),
                ],
              );
            case 'step_result':
              final steps = [...msg.steps];
              if (steps.isNotEmpty) {
                final last = steps.removeLast();
                steps.add(AgentChatEvent(
                    type: 'step_result',
                    name: event.name,
                    result: event.result));
                _messages[idx] = AgentChatMessage(
                    role: 'assistant', content: msg.content, steps: steps);
              }
            case 'reply':
              // reply 为完整回复兜底：token 为空时直接使用
              if (msg.content.isEmpty) {
                _messages[idx] = AgentChatMessage(
                    role: 'assistant', content: event.content, steps: msg.steps);
              }
            default:
              break;
          }
        });
      },
      onError: (Object e) {
        _finishSending(error: t.agentChatNetworkError(e.toString()));
      },
      onDone: () {
        _finishSending();
      },
    );
  }

  void _finishSending({String? error}) {
    if (!mounted) return;
    setState(() {
      _sending = false;
      _activeAssistantIndex = null;
      // 空回复时给占位提示
      if (error != null) {
        _messages.add(AgentChatMessage(role: 'assistant', content: error));
      }
      final last = _messages.isEmpty ? null : _messages.last;
      if (last != null &&
          last.role == 'assistant' &&
          last.content.isEmpty &&
          error == null) {
        _messages[_messages.length - 1] =
            const AgentChatMessage(role: 'assistant', content: '（无回复）');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      key: const Key('agent_chat_screen'),
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildHeader(t, cs),
          const Divider(height: 1),
          if (_toolsError != null) _buildToolsError(t),
          if (_toolsInfo != null) _buildToolSelectors(t, cs),
          Expanded(child: _buildMessageList()),
          _buildInputBar(t, cs),
        ],
      ),
    );
  }

  Widget _buildHeader(AppLocalizations t, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 12),
      child: Row(
        children: [
          Icon(RemixIcon.robotLine, color: cs.primary, size: 22),
          const SizedBox(width: 8),
          Text(
            t.agentChatTitle,
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, color: cs.onSurface),
          ),
          const Spacer(),
          IconButton(
            key: const Key('agent_chat_close'),
            icon: Icon(RemixIcon.closeLine, color: cs.onSurfaceVariant),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildToolsError(AppLocalizations t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Icon(RemixIcon.errorWarningLine,
              color: Theme.of(context).colorScheme.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t.agentChatLoadFailed(_toolsError ?? ''),
              style: TextStyle(
                  fontSize: 13, color: Theme.of(context).colorScheme.error),
            ),
          ),
          TextButton(
            key: const Key('agent_tools_retry'),
            onPressed: _loadTools,
            child: Text(t.msgRetry),
          ),
        ],
      ),
    );
  }

  Widget _buildToolSelectors(AppLocalizations t, ColorScheme cs) {
    final info = _toolsInfo!;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest.withAlpha(120),
        border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChipRow(
            label: t.agentChatSkillLabel,
            items: info.skills,
            selected: _selectedSkills,
          ),
          if (info.tools.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildChipRow(
              label: t.agentChatToolLabel,
              items: info.tools,
              selected: _selectedTools,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChipRow({
    required String label,
    required List<AgentToolMeta> items,
    required Set<String> selected,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: items.map((item) {
              final isSelected = selected.contains(item.name);
              return FilterChip(
                key: Key('agent_tool_chip_${item.name}'),
                label: Text(item.name,
                    style: const TextStyle(fontSize: 11.5)),
                selected: isSelected,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: (_) =>
                    _toggleSelection(selected, item.name),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageList() {
    final t = AppLocalizations.of(context)!;
    if (_messages.isEmpty && !_sending) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            t.agentChatInputHint,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return _MessageBubble(message: msg);
      },
    );
  }

  Widget _buildInputBar(AppLocalizations t, ColorScheme cs) {
    final canSend = _inputController.text.trim().isNotEmpty && !_sending;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                key: const Key('agent_input_field'),
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: t.agentChatInputHint,
                  isDense: true,
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withAlpha(90),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _send(),
                textInputAction: TextInputAction.send,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const Key('agent_send_button'),
              icon: Icon(canSend ? RemixIcon.sendPlaneFill : RemixIcon.sendPlaneLine,
                  size: 22),
              color: canSend ? cs.primary : cs.onSurfaceVariant.withAlpha(80),
              onPressed: canSend ? _send : null,
              tooltip: t.agentChatSend,
            ),
          ],
        ),
      ),
    );
  }
}

/// 单条消息气泡：用户消息右对齐，助手消息左对齐并附带工具步骤。
class _MessageBubble extends StatelessWidget {
  final AgentChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isUser = message.role == 'user';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: isUser ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.steps.isNotEmpty) _buildSteps(context),
            Text(
              message.content,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: isUser ? cs.onPrimary : cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSteps(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: message.steps.map((step) {
          final icon = step.type == 'step_result'
              ? RemixIcon.checkboxCircleFill
              : RemixIcon.timeLine;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cs.primary.withAlpha(18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: cs.primary),
                const SizedBox(width: 4),
                Text(step.name,
                    style: TextStyle(fontSize: 11, color: cs.primary)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
