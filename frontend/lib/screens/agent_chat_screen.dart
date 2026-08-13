import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/screens/ai_providers_screen.dart';
import 'package:mobile_portainer_flutter_module/screens/hermes_config_screen.dart';
import 'package:mobile_portainer_flutter_module/services/agent_service.dart';
import 'package:mobile_portainer_flutter_module/services/platform/preferences_service.dart';
import 'package:mobile_portainer_flutter_module/utils/platform_detector.dart';

/// 快捷指令（issue #26）：输入框下方的 Docker 运维常用指令。
/// 点击后填入输入框（可编辑后发送），不直接发送。
/// 第二轮按参考图样式：纯文字胶囊（无图标）。
class AgentQuickCommand {
  final String id; // chip 的 Key 后缀：agent_quick_chip_<id>
  final String label; // 显示名（i18n）
  final String prompt; // 点击后填入输入框的完整指令（i18n）

  const AgentQuickCommand({
    required this.id,
    required this.label,
    required this.prompt,
  });
}

/// Docker 运维常用快捷指令（issue #26）：
/// 拉取镜像、运行容器、配置环境变量、查看日志、清理镜像、容器状态。
List<AgentQuickCommand> agentQuickCommands(AppLocalizations t) => [
      AgentQuickCommand(
        id: 'pull_image',
        label: t.agentChatQuickPullImage,
        prompt: t.agentChatQuickPullImagePrompt,
      ),
      AgentQuickCommand(
        id: 'run_container',
        label: t.agentChatQuickRunContainer,
        prompt: t.agentChatQuickRunContainerPrompt,
      ),
      AgentQuickCommand(
        id: 'env_var',
        label: t.agentChatQuickEnvVar,
        prompt: t.agentChatQuickEnvVarPrompt,
      ),
      AgentQuickCommand(
        id: 'logs',
        label: t.agentChatQuickLogs,
        prompt: t.agentChatQuickLogsPrompt,
      ),
      AgentQuickCommand(
        id: 'clean_images',
        label: t.agentChatQuickCleanImages,
        prompt: t.agentChatQuickCleanImagesPrompt,
      ),
      AgentQuickCommand(
        id: 'status',
        label: t.agentChatQuickStatus,
        prompt: t.agentChatQuickStatusPrompt,
      ),
    ];

/// AI agent 聊天框（issue #21）。
///
/// 入口 [AgentChatDialog.show]：按项目对话框规则分端弹出——
/// 手机端（Android/iOS/鸿蒙）showModalBottomSheet 底部弹出；
/// Web/桌面等非手机端 showDialog 居中对话框。
///
/// 功能：发送 prompt、选择 skill（默认 backend/skills 两个）与
/// tools（后端 MCP server 的 Docker 管理工具），经后端
/// /admin/agent/chat/stream（SSE）流式对话，token 增量渲染。
///
/// 界面风格参考 Codex：消息无气泡流式布局（角色标签 + 头像区分）、
/// 毛玻璃圆角输入区 + 圆形渐变发送按钮、简洁头部。
class AgentChatDialog {
  static void show(BuildContext context, {String? initialMessage}) {
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
          child: AgentChatScreen(initialMessage: initialMessage),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          contentPadding: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          content: SizedBox(
            width: 560,
            height: 680,
            child: AgentChatScreen(initialMessage: initialMessage),
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
  const AgentChatScreen({super.key, this.initialMessage});

  final String? initialMessage;

  @override
  State<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends State<AgentChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode(); // issue #26：快捷指令填入后聚焦
  bool _inputFocused = false; // 输入框聚焦态（边框高亮）

  final List<AgentChatMessage> _messages = [];
  AgentToolsInfo? _toolsInfo;
  String? _toolsError;
  Set<String> _selectedSkills = {};
  Set<String> _selectedTools = {};
  bool _sending = false;
  bool _initialMessageSent = false;
  StreamSubscription<AgentChatEvent>? _subscription;

  // 当前正在生成的助手消息索引（流式 token 追加目标）
  int? _activeAssistantIndex;

  @override
  void initState() {
    super.initState();
    _inputFocus.addListener(() {
      if (mounted && _inputFocused != _inputFocus.hasFocus) {
        setState(() => _inputFocused = _inputFocus.hasFocus);
      }
    });
    unawaited(_loadTools().whenComplete(_sendInitialMessage));
  }

  void _sendInitialMessage() {
    final message = widget.initialMessage?.trim();
    if (_initialMessageSent || message == null || message.isEmpty || !mounted) {
      return;
    }
    _initialMessageSent = true;
    _inputController.text = message;
    _send();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _inputController.dispose();
    _inputFocus.dispose();
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

  /// 快捷指令填入输入框（issue #26）：替换输入并聚焦到末尾，
  /// 由用户确认/编辑后手动发送。
  void _fillQuickCommand(String prompt) {
    _inputController.text = prompt;
    _inputController.selection =
        TextSelection.collapsed(offset: prompt.length);
    setState(() {});
    _inputFocus.requestFocus();
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

  /// 清空对话（Codex 风格：header 清空按钮）。
  void _clearConversation() {
    _subscription?.cancel();
    _subscription = null;
    setState(() {
      _messages.clear();
      _activeAssistantIndex = null;
      _sending = false;
    });
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
                steps.removeLast();
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
        // AgentChatHttpException 携带后端可读 detail；其余剥掉 "Exception: " 前缀
        final message = e is AgentChatHttpException
            ? e.message
            : e.toString().replaceFirst(RegExp(r'^Exception: '), '');
        _finishSending(error: t.agentChatNetworkError(message));
        // 结构化错误码 llm_not_configured：弹出提示并引导配置（issue #23）
        if (e is AgentChatHttpException &&
            e.errorCode == 'llm_not_configured') {
          _showLlmNotConfiguredPrompt(t);
        }
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

  /// LLM 未配置（503，error_code=llm_not_configured）时弹出提示，
  /// 提供双入口：配置 Hermes / 配置 AI 供应商（issue #21 第四轮）。
  ///
  /// 按项目对话框规则分端：手机端 showModalBottomSheet；
  /// 其他端（Web/桌面）showDialog + AlertDialog。
  void _showLlmNotConfiguredPrompt(AppLocalizations t) {
    if (!mounted) return;
    final isMobile = PlatformDetector.isAndroid ||
        PlatformDetector.isIOS ||
        PlatformDetector.isOhos;

    void goConfigure(Widget screen) {
      // 先关闭提示层（对话框/底部菜单），再从聊天界面跳转配置页
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => screen),
      );
    }

    if (isMobile) {
      showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) {
          final cs = Theme.of(sheetContext).colorScheme;
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(
              key: const Key('llm_not_configured_dialog'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.agentChatLlmNotConfiguredTitle,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
                const SizedBox(height: 8),
                Text(t.agentChatLlmNotConfiguredBody,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: Text(t.actionCancel),
                  ),
                  TextButton(
                    onPressed: () =>
                        goConfigure(const HermesConfigScreen()),
                    child: Text(t.agentChatGoConfigureHermes),
                  ),
                  FilledButton(
                    onPressed: () => goConfigure(const AiProvidersScreen()),
                    child: Text(t.agentChatGoConfigureProvider),
                  ),
                ]),
              ],
            ),
          );
        },
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          key: const Key('llm_not_configured_dialog'),
          icon: Icon(RemixIcon.errorWarningLine, color: cs.error, size: 28),
          title: Text(t.agentChatLlmNotConfiguredTitle),
          content: Text(t.agentChatLlmNotConfiguredBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(t.actionCancel),
            ),
            TextButton(
              onPressed: () => goConfigure(const HermesConfigScreen()),
              child: Text(t.agentChatGoConfigureHermes),
            ),
            FilledButton(
              onPressed: () => goConfigure(const AiProvidersScreen()),
              child: Text(t.agentChatGoConfigureProvider),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      key: const Key('agent_chat_screen'),
      color: cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildHeader(t, cs),
          if (_toolsError != null) _buildToolsError(t),
          if (_toolsInfo != null) _buildToolSelectors(t, cs),
          Expanded(child: _buildMessageList()),
          _buildStatusBar(t, cs),
          _buildInputBar(t, cs),
        ],
      ),
    );
  }

  // ---- Header（Codex 简洁风格）----

  Widget _buildHeader(AppLocalizations t, ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [cs.primary.withAlpha(12), Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 12),
      child: Row(
        children: [
          // 渐变圆角 logo
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [cs.primary, cs.tertiary],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(RemixIcon.aiAgentFill, color: cs.onPrimary, size: 17),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.agentChatTitle,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.green.shade500,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    t.agentChatSubtitle,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          // 清空对话（有消息时显示）
          if (_messages.isNotEmpty)
            IconButton(
              key: const Key('agent_clear_button'),
              icon: Icon(RemixIcon.deleteBinLine,
                  color: cs.onSurfaceVariant, size: 20),
              onPressed: _clearConversation,
              tooltip: t.agentChatClear,
            ),
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

  // ---- 工具加载失败 ----

  Widget _buildToolsError(AppLocalizations t) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.error.withAlpha(10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.error.withAlpha(60), width: 0.5),
        ),
        child: Row(
          children: [
            Icon(RemixIcon.errorWarningLine, color: cs.error, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t.agentChatLoadFailed(_toolsError ?? ''),
                style: TextStyle(fontSize: 13, color: cs.error),
              ),
            ),
            TextButton(
              key: const Key('agent_tools_retry'),
              onPressed: _loadTools,
              child: Text(t.msgRetry),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 工具选择器（胶囊卡片）----

  Widget _buildToolSelectors(AppLocalizations t, ColorScheme cs) {
    final info = _toolsInfo!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest.withAlpha(130),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: cs.outlineVariant.withAlpha(120), width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildChipRow(
              label: t.agentChatSkillLabel,
              icon: RemixIcon.puzzleLine,
              items: info.skills,
              selected: _selectedSkills,
            ),
            if (info.tools.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildChipRow(
                label: t.agentChatToolLabel,
                icon: RemixIcon.functions,
                items: info.tools,
                selected: _selectedTools,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChipRow({
    required String label,
    required IconData icon,
    required List<AgentToolMeta> items,
    required Set<String> selected,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: items.map((item) {
              final isSelected = selected.contains(item.name);
              return FilterChip(
                key: Key('agent_tool_chip_${item.name}'),
                label: Text(item.name,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isSelected ? cs.primary : cs.onSurfaceVariant,
                      fontWeight: isSelected ? FontWeight.w600 : null,
                    )),
                selected: isSelected,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: Colors.transparent,
                selectedColor: cs.primary.withAlpha(24),
                side: BorderSide(
                  color:
                      isSelected ? cs.primary.withAlpha(140) : cs.outlineVariant,
                  width: 1,
                ),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 1),
                onSelected: (_) => _toggleSelection(selected, item.name),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ---- 消息列表（Codex 无气泡流式）----

  Widget _buildMessageList() {
    if (_messages.isEmpty && !_sending) {
      return _buildEmptyState();
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return _MessageBubble(message: msg);
      },
    );
  }

  /// 空状态：渐变 logo + 引导文案（Codex 风格）。
  Widget _buildEmptyState() {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cs.primary, cs.tertiary],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: cs.primary.withAlpha(64),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(RemixIcon.aiAgentLine, color: cs.onPrimary, size: 30),
            ),
            const SizedBox(height: 20),
            Text(
              t.agentChatEmptyTitle,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              t.agentChatEmptyDesc,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, height: 1.5, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// 状态条：发送中"思考中…" / 工具全不选提示。
  Widget _buildStatusBar(AppLocalizations t, ColorScheme cs) {
    Widget content;
    if (_sending) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              key: const Key('agent_thinking_indicator'),
              strokeWidth: 2,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(t.agentChatSending,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ],
      );
    } else if (_toolsInfo != null &&
        _selectedSkills.isEmpty &&
        _selectedTools.isEmpty) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(RemixIcon.informationLine, size: 14, color: cs.tertiary),
          const SizedBox(width: 6),
          Text(t.agentChatEmptyTools,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ],
      );
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Align(alignment: Alignment.centerLeft, child: content),
    );
  }

  // ---- 输入栏（Codex 毛玻璃圆角 + 圆形渐变发送按钮 + 快捷指令）----

  Widget _buildInputBar(AppLocalizations t, ColorScheme cs) {
    final canSend = _inputController.text.trim().isNotEmpty && !_sending;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 输入条：左侧 AI 图标 + 聚焦高亮边框（issue #26 视觉优化）
            // 第二轮按参考图：浅色模式白底；深色模式保持半透明分层灰。
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              decoration: BoxDecoration(
                color: cs.brightness == Brightness.light
                    ? cs.surfaceContainerLowest
                    : cs.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _inputFocused
                      ? cs.primary.withAlpha(170)
                      : cs.outlineVariant.withAlpha(140),
                  width: _inputFocused ? 1 : 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(14),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // 左侧圆形渐变 AI 图标（参考图样式：圆形 + sparkle）
                  Container(
                    key: const Key('agent_input_ai_icon'),
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [cs.primary, cs.tertiary],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(RemixIcon.sparklingFill,
                        color: cs.onPrimary, size: 14),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      focusNode: _inputFocus,
                      key: const Key('agent_input_field'),
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: t.agentChatInputHint,
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _send(),
                      textInputAction: TextInputAction.send,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 圆形渐变发送按钮（发送中显示 loader）
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: canSend
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [cs.primary, cs.tertiary],
                            )
                          : LinearGradient(
                              colors: [
                                cs.surfaceContainerHighest,
                                cs.surfaceContainerHighest,
                              ],
                            ),
                      boxShadow: canSend
                          ? [
                              BoxShadow(
                                color: cs.primary.withAlpha(120),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : const [],
                    ),
                    child: IconButton(
                      key: const Key('agent_send_button'),
                      padding: EdgeInsets.zero,
                      icon: _sending
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.onPrimary,
                              ),
                            )
                          : Icon(
                              canSend
                                  ? RemixIcon.sendPlaneFill
                                  : RemixIcon.sendPlaneLine,
                              size: 18,
                            ),
                      color: cs.onPrimary,
                      disabledColor: cs.onSurfaceVariant.withAlpha(90),
                      onPressed: canSend ? _send : null,
                      tooltip: t.agentChatSend,
                    ),
                  ),
                ],
              ),
            ),
            // 快捷指令行（issue #26）：Docker 运维常用指令
            _buildQuickCommands(t, cs),
          ],
        ),
      ),
    );
  }

  /// 快捷指令行：横向滚动的一排 Docker 常用指令，
  /// 点击填入输入框（不直接发送）。发送中禁用。
  /// 第二轮按参考图样式：浅蓝底胶囊（primaryContainer）、深色文字、
  /// 无图标、淡蓝描边。
  Widget _buildQuickCommands(AppLocalizations t, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SingleChildScrollView(
        key: const Key('agent_quick_commands'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: agentQuickCommands(t).map((command) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                key: Key('agent_quick_chip_${command.id}'),
                label: Text(
                  command.label,
                  style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer),
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: cs.primaryContainer,
                side: BorderSide(
                  color: cs.primary.withAlpha(80),
                  width: 0.5,
                ),
                shape: const StadiumBorder(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                onPressed:
                    _sending ? null : () => _fillQuickCommand(command.prompt),
                tooltip: command.prompt,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// 单条消息（Codex 风格）：无气泡，角色标签 + 文本直接铺开；
/// 用户消息右对齐带"你"标签，助手消息左对齐带渐变头像与工具徽章。
class _MessageBubble extends StatelessWidget {
  final AgentChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isUser = message.role == 'user';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        constraints: const BoxConstraints(maxWidth: 430),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // 角色行：用户"你"标签 / 助手渐变头像 + 名称
            if (isUser)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration:
                        BoxDecoration(shape: BoxShape.circle, color: cs.primary),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    t.agentChatYou,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [cs.primary, cs.tertiary],
                      ),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(RemixIcon.robotLine,
                        color: cs.onPrimary, size: 13),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    t.agentChatTitle,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            const SizedBox(height: 6),
            // 工具执行步骤徽章（助手消息）
            if (message.steps.isNotEmpty) ...[
              _buildSteps(context),
              const SizedBox(height: 6),
            ],
            // 消息文本：无气泡直接铺开
            Text(
              message.content,
              style: TextStyle(
                fontSize: 15,
                height: 1.55,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSteps(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final doneColor = Colors.green.shade600;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: message.steps.map((step) {
        final isDone = step.type == 'step_result';
        final color = isDone ? doneColor : cs.primary;
        final icon =
            isDone ? RemixIcon.checkboxCircleFill : RemixIcon.timeLine;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withAlpha(14),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withAlpha(70), width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(step.name,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w500, color: color)),
            ],
          ),
        );
      }).toList(),
    );
  }
}
