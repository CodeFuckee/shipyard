import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/utils/notify_utils.dart';
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
    final calculatedWidth = items.length * itemWidth + innerPadding;

    return SafeArea(
      child: Center(
        heightFactor: 1.0,
        child: Container(
          key: const Key('main_bottom_nav_bar'),
          margin: EdgeInsets.fromLTRB(20, 0, 20,
              (PlatformDetector.isOhos || PlatformDetector.isAndroid || PlatformDetector.isIOS) ? 0 : 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(34),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: SizedBox(
                width: calculatedWidth,
                height: 68,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(items.length, (index) {
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
                  }),
                ),
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
