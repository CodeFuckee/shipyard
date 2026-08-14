import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/utils/notify_utils.dart';
import 'agent_chat_screen.dart';
import 'dashboard_screen.dart';
import 'resources_screen.dart';
import 'projects_screen.dart';
import 'settings_screen.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import '../utils/platform_detector.dart';


class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _selectedIndex = 0;
  bool _settingsChanged = false;
  bool _isAgentComposerOpen = false;
  bool _agentBtnPressed = false;
  final TextEditingController _agentDraftController = TextEditingController();
  final FocusNode _agentDraftFocusNode = FocusNode();
  // 资源页内当前激活的 tab（0 = 容器），用于控制 AppBar 布局切换按钮
  int _resourcesTabIndex = 0;

  final GlobalKey<DashboardScreenState> _dashboardKey =
      GlobalKey<DashboardScreenState>();
  final GlobalKey<ResourcesScreenState> _resourcesKey =
      GlobalKey<ResourcesScreenState>();
  // Keys for other screens are no longer needed as they are navigated to from Resources
  final GlobalKey<ProjectListScreenState> _projectsKey =
      GlobalKey<ProjectListScreenState>();
  final GlobalKey<SettingsScreenState> _settingsKey =
      GlobalKey<SettingsScreenState>();

  @override
  void dispose() {
    _agentDraftController.dispose();
    _agentDraftFocusNode.dispose();
    super.dispose();
  }

  void _openAgentComposer() {
    setState(() => _isAgentComposerOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _agentDraftFocusNode.requestFocus();
    });
  }

  void _closeAgentComposer() {
    _agentDraftFocusNode.unfocus();
    _agentDraftController.clear();
    setState(() => _isAgentComposerOpen = false);
  }

  void _sendAgentDraft() {
    final message = _agentDraftController.text.trim();
    if (message.isEmpty) return;
    _agentDraftFocusNode.unfocus();
    _agentDraftController.clear();
    setState(() => _isAgentComposerOpen = false);
    AgentChatDialog.show(context, initialMessage: message);
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    if (_settingsChanged) {
      _dashboardKey.currentState?.refresh();
      _resourcesKey.currentState?.refreshAfterSettings();
      _projectsKey.currentState?.refresh();
      // Other screens will refresh when opened as they are pushed new
      _settingsChanged = false;
    }
    // Also refresh settings if we switch to it, to ensure it shows correct active server
    if (index == 3) {
      _settingsKey.currentState?.refresh();
    }
  }

  String _getTitle(AppLocalizations t) {
    switch (_selectedIndex) {
      case 0:
        return t.titleDashboard;
      case 1:
        return t.titleResources;
      case 2:
        return t.titleProjects;
      case 3:
        return t.titleSettings;
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    final bottomNavBar = _buildCustomBottomNavBar(context, t);

    final body = IndexedStack(
      index: _selectedIndex,
      children: [
        DashboardScreen(
          key: _dashboardKey,
          onSwitchToContainers: () {
            _settingsKey.currentState?.refresh();
            _onItemTapped(1);
            _resourcesKey.currentState?.activateTab(0);
            // issue #20：概览页切换服务器后 prefs 已更新为新的
            // docker_api_url，容器页（IndexedStack 常驻）不会自动重读，
            // 必须显式刷新资源页各 tab，否则仍显示旧服务器的容器
            _resourcesKey.currentState?.refreshAfterSettings();
          },
          onSwitchToImages: () {
            _settingsKey.currentState?.refresh();
            _onItemTapped(1);
            _resourcesKey.currentState?.activateTab(1);
            // 与容器 tab 同理：切镜像前先重读服务器配置并刷新
            _resourcesKey.currentState?.refreshAfterSettings();
          },
        ),
        ResourcesScreen(
          key: _resourcesKey,
          bottomNavBar: bottomNavBar,
          onTabChanged: (index) {
            if (!mounted || _resourcesTabIndex == index) return;
            setState(() {
              _resourcesTabIndex = index;
            });
          },
        ),
        ProjectListScreen(
          key: _projectsKey,
        ),
        SettingsScreen(
          key: _settingsKey,
          onSaved: () {
            _settingsChanged = true;
            _onItemTapped(0);
            NotifyUtils.showNotify(context, t.msgSettingsSaved);
          },
        ),
      ],
    );

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(_getTitle(t)),
        actions: _buildActions(t),
      ),
      body: Stack(
        children: [
          body,
          if (_selectedIndex != 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: bottomNavBar,
            ),
        ],
      ),
    );
  }

  Widget _buildCustomBottomNavBar(BuildContext context, AppLocalizations t) {
    final colorScheme = Theme.of(context).colorScheme;
    final items = [
      (RemixIcon.dashboardLine, RemixIcon.dashboardFill, t.titleDashboard),
      (RemixIcon.apps2Line, RemixIcon.apps2Fill, t.titleResources),
      (RemixIcon.folderLine, RemixIcon.folderFill, t.titleProjects),
      (RemixIcon.settings3Line, RemixIcon.settings3Line, t.titleSettings),
    ];

    const double itemWidth = 72.0;
    const double innerPadding = 24.0;
    final calculatedWidth = (items.length + 1) * itemWidth + innerPadding;

    final tabWidgets = List<Widget>.generate(items.length, (index) {
      final isSelected = _selectedIndex == index;
      final item = items[index];
      return Expanded(
        child: GestureDetector(
          onTap: () => _onItemTapped(index),
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? item.$2 : item.$1,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.8),
                size: 26,
              ),
              const SizedBox(height: 4),
              Text(
                item.$3,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      );
    });
    tabWidgets.insert(items.length ~/ 2, _buildAgentButton(context, t));

    // issue #27：AI 助手展开后输入条接近全宽，两边只留少量空隙；
    // 导航栏状态保持固定宽度与原有边距不变。
    const double composerGap = 12.0;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final composerWidth = screenWidth - composerGap * 2;
    final horizontalMargin =
        _isAgentComposerOpen ? composerGap : 20.0;

    return SafeArea(
      child: Center(
        heightFactor: 1.0,
        child: Container(
          key: const Key('main_bottom_nav_bar'),
          margin: EdgeInsets.fromLTRB(horizontalMargin, 0, horizontalMargin,
              (PlatformDetector.isOhos || PlatformDetector.isAndroid || PlatformDetector.isIOS) ? 0 : 16),
          child: _isAgentComposerOpen
              ? _buildAgentComposer(context, t, composerWidth)
              : _buildNavigationBar(tabWidgets, calculatedWidth),
        ),
      ),
    );
  }

  Widget _buildNavigationBar(List<Widget> tabWidgets, double width) {
    return ClipRRect(
      key: const ValueKey('bottom_navigation'),
      borderRadius: BorderRadius.circular(34),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: SizedBox(
          width: width,
          height: 68,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: tabWidgets,
          ),
        ),
      ),
    );
  }

  Widget _buildAgentComposer(
    BuildContext context,
    AppLocalizations t,
    double width,
  ) {
    final cs = Theme.of(context).colorScheme;
    final canSend = _agentDraftController.text.trim().isNotEmpty;
    final quickItems = <({IconData icon, String label})>[
      (icon: RemixIcon.sparklingFill, label: t.agentComposerQuick),
      (icon: RemixIcon.terminalBoxLine, label: t.agentComposerDockerCommand),
      (icon: RemixIcon.serverLine, label: t.agentComposerContainerStatus),
      (icon: RemixIcon.fileTextLine, label: t.agentComposerViewLogs),
      (icon: RemixIcon.deleteBinLine, label: t.agentComposerCleanImages),
      (icon: RemixIcon.more2Line, label: t.agentComposerMore),
    ];
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        key: const ValueKey('bottom_agent_composer'),
        width: width,
        height: 124,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  IconButton(
                    key: const Key('bottom_agent_close'),
                    onPressed: _closeAgentComposer,
                    icon: const Icon(RemixIcon.arrowLeftLine),
                    tooltip: '返回导航',
                  ),
                  Expanded(
                    child: TextField(
                      key: const Key('bottom_agent_input'),
                      controller: _agentDraftController,
                      focusNode: _agentDraftFocusNode,
                      minLines: 1,
                      maxLines: 1,
                      textInputAction: TextInputAction.send,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _sendAgentDraft(),
                      decoration: InputDecoration(
                        hintText: t.agentChatInputHint,
                        hintStyle: TextStyle(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.72),
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: canSend
                          ? LinearGradient(colors: [cs.primary, cs.tertiary])
                          : null,
                      color: canSend ? null : cs.surfaceContainerHighest,
                    ),
                    child: IconButton(
                      key: const Key('bottom_agent_send'),
                      icon: Icon(
                        canSend ? RemixIcon.arrowUpLine : RemixIcon.sendPlaneLine,
                        size: 19,
                      ),
                      color: canSend ? cs.onPrimary : cs.onSurfaceVariant,
                      tooltip: t.agentChatSend,
                      onPressed: canSend ? _sendAgentDraft : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 42,
              child: SingleChildScrollView(
                key: const Key('bottom_agent_quick_items'),
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(RemixIcon.addLine, size: 22),
                    ),
                    Container(width: 1, height: 22, color: cs.outlineVariant),
                    const SizedBox(width: 10),
                    ...quickItems.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(right: 18),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(item.icon, size: 18, color: cs.onSurface),
                            const SizedBox(width: 6),
                            Text(
                              item.label,
                              style: TextStyle(
                                color: cs.onSurface,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 导航栏正中间的 AI agent 按钮（Codex 风格美化）：
  /// 渐变主体 + 背景色外环 + 双层光晕，按压缩放反馈，点击弹出聊天框。
  Widget _buildAgentButton(BuildContext context, AppLocalizations t) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Center(
        child: Tooltip(
          message: t.agentChatToolTip,
          child: GestureDetector(
            key: const Key('agent_chat_button'),
            onTap: _openAgentComposer,
            onTapDown: (_) => setState(() => _agentBtnPressed = true),
            onTapUp: (_) => setState(() => _agentBtnPressed = false),
            onTapCancel: () => setState(() => _agentBtnPressed = false),
            behavior: HitTestBehavior.opaque,
            child: AnimatedScale(
              scale: _agentBtnPressed ? 0.86 : 1.0,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // 背景色外环，与导航栏产生层次
                  border: Border.all(
                    color: Theme.of(context)
                        .scaffoldBackgroundColor
                        .withValues(alpha: 0.9),
                    width: 3,
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [colorScheme.primary, colorScheme.tertiary],
                  ),
                  boxShadow: [
                    // 近距阴影 + 远距光晕
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.38),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.16),
                      blurRadius: 22,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(RemixIcon.aiAgentLine,
                    color: colorScheme.onPrimary, size: 25),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions(AppLocalizations t) {
    final bool containersTabActive =
        _selectedIndex == 1 && _resourcesTabIndex == 0;
    final String currentEffectiveMode =
        _resourcesKey.currentState?.containerLayoutMode ?? 'grid';

    return [
      // 容器布局切换（资源页 + 容器 tab 激活时显示）
      if (containersTabActive)
        IconButton(
          icon: Icon(currentEffectiveMode == 'grid'
              ? RemixIcon.listUnordered
              : RemixIcon.gridLine),
          onPressed: _resourcesKey.currentState?.toggleLayoutMode,
          tooltip: 'Switch Layout',
        ),
      if (_selectedIndex == 0 || _selectedIndex == 1 || _selectedIndex == 2)
        IconButton(
          icon: const Icon(RemixIcon.refreshLine),
          onPressed: () {
            if (_selectedIndex == 0) {
              _dashboardKey.currentState?.refresh();
            } else if (_selectedIndex == 1) {
              _resourcesKey.currentState?.refreshCurrentTab();
            } else if (_selectedIndex == 2) {
              if (_projectsKey.currentState?.isLoading != true) {
                _projectsKey.currentState?.manualRefresh();
              }
            }
          },
        ),
      const SizedBox(width: 4),
      Tooltip(
        message: (_resourcesKey.currentState?.isContainersWsConnected ?? false)
            ? t.msgWsConnected
            : t.msgWsDisconnected,
        child: Icon(
          (_resourcesKey.currentState?.isContainersWsConnected ?? false)
              ? RemixIcon.cloudLine
              : RemixIcon.cloudOffLine,
          color: (_resourcesKey.currentState?.isContainersWsConnected ?? false)
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }

}
