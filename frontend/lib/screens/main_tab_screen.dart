import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/utils/notify_utils.dart';
import 'dashboard_screen.dart';
import 'home_screen.dart';
import 'images_screen.dart';
import 'resources_screen.dart';
import 'projects_screen.dart';
import 'settings_screen.dart';
import '../theme/app_theme.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/services/platform/preferences_service.dart';
import '../utils/platform_detector.dart';


class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _selectedIndex = 0;
  bool _settingsChanged = false;
  String _containerLayoutMode = 'grid';

  final GlobalKey<DashboardScreenState> _dashboardKey =
      GlobalKey<DashboardScreenState>();
  final GlobalKey<HomeScreenState> _containersKey =
      GlobalKey<HomeScreenState>();
  final GlobalKey<ImagesScreenState> _imagesKey =
      GlobalKey<ImagesScreenState>();
  // Keys for other screens are no longer needed as they are navigated to from Resources
  final GlobalKey<ProjectListScreenState> _projectsKey =
      GlobalKey<ProjectListScreenState>();
  final GlobalKey<SettingsScreenState> _settingsKey =
      GlobalKey<SettingsScreenState>();

  @override
  void initState() {
    super.initState();
    _loadLayoutPreference();
  }

  Future<void> _loadLayoutPreference() async {
    final prefs = await PreferencesService.getInstance();
    if (!mounted) return;
    setState(() {
      // _dashboardLayoutMode = prefs.getString('dashboard_layout_mode') ?? 'auto';
      _containerLayoutMode = prefs.getString('container_layout_mode') ?? 'grid';
    });
  }

  Future<void> _toggleLayoutMode() async {
    // final screenWidth = MediaQuery.of(context).size.width;
    final prefs = await PreferencesService.getInstance();
    // final isWide = screenWidth >= 600;

    if (_selectedIndex == 1) {
      // Container toggle
      // For containers, we only have 'grid' (normal) or 'list' (compact)
      // 'grid' means Card view (GridView on wide, Card List on narrow)
      // 'list' means Compact Tile view (List view always)
      String newMode = _containerLayoutMode == 'grid' ? 'list' : 'grid';
      
      await prefs.setString('container_layout_mode', newMode);
      
      if (!mounted) return;
      setState(() {
        _containerLayoutMode = newMode;
      });
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    if (_settingsChanged) {
      _dashboardKey.currentState?.refresh();
      _containersKey.currentState?.refreshAfterSettings();
      _imagesKey.currentState?.refreshAfterSettings();
      _projectsKey.currentState?.refresh();
      // Other screens will refresh when opened as they are pushed new
      _settingsChanged = false;
    }
    // Also refresh settings if we switch to it, to ensure it shows correct active server
    if (index == 4) {
      _settingsKey.currentState?.refresh();
    }
  }

  String _getTitle(AppLocalizations t) {
    switch (_selectedIndex) {
      case 0:
        return t.titleDashboard;
      case 1:
        return t.titleContainers;
      case 2:
        return t.titleResources;
      case 3:
        return t.titleProjects;
      case 4:
        return t.titleSettings;
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    String currentEffectiveMode = 'list';
    if (_selectedIndex == 1) {
      currentEffectiveMode = _containerLayoutMode;
    }

    final bottomNavBar = _buildCustomBottomNavBar(context, t);

    final body = IndexedStack(
      index: _selectedIndex,
      children: [
        DashboardScreen(
          key: _dashboardKey,
          onSwitchToContainers: () {
            _containersKey.currentState?.refreshAfterSettings();
            _settingsKey.currentState?.refresh();
            _onItemTapped(1);
          },
          onSwitchToImages: () {
            _settingsKey.currentState?.refresh();
            _onItemTapped(2);
          },
        ),
        HomeScreen(
          key: _containersKey,
          layoutMode: _containerLayoutMode,
        ),
        ResourcesScreen(
          bottomNavBar: bottomNavBar,
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
        actions: _buildActions(t, currentEffectiveMode),
      ),
      body: Stack(
        children: [
          body,
          if (_selectedIndex != 2)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: bottomNavBar,
            ),
          if (_selectedIndex == 1)
            Positioned(
              right: 16,
              bottom: AppTheme.fabBottomInset,
              child: FloatingActionButton(
                heroTag: 'fab_run_container',
                onPressed: () {
                  _containersKey.currentState?.showRunContainerDialog();
                },
                child: const Icon(RemixIcon.addLine),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCustomBottomNavBar(BuildContext context, AppLocalizations t) {
    final colorScheme = Theme.of(context).colorScheme;
    final items = [
      (RemixIcon.dashboardLine, RemixIcon.dashboardFill, t.titleDashboard),
      (RemixIcon.serverLine, RemixIcon.serverLine, t.titleContainers),
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

  List<Widget> _buildActions(AppLocalizations t, String currentEffectiveMode) {
    return [
      if (_selectedIndex == 1)
        IconButton(
          icon: Icon(currentEffectiveMode == 'grid'
              ? RemixIcon.listUnordered
              : RemixIcon.gridLine),
          onPressed: _toggleLayoutMode,
          tooltip: 'Switch Layout',
        ),
      if (_selectedIndex == 0 || _selectedIndex == 1 || _selectedIndex == 3)
        IconButton(
          icon: const Icon(RemixIcon.refreshLine),
          onPressed: () {
            if (_selectedIndex == 0) {
              _dashboardKey.currentState?.refresh();
            } else if (_selectedIndex == 1) {
              if (_containersKey.currentState?.isLoading != true) {
                _containersKey.currentState?.manualRefresh();
              }
            } else if (_selectedIndex == 3) {
              if (_projectsKey.currentState?.isLoading != true) {
                _projectsKey.currentState?.manualRefresh();
              }
            }
          },
        ),
      const SizedBox(width: 4),
      Tooltip(
        message: (_containersKey.currentState?.isWsConnected ?? false)
            ? t.msgWsConnected
            : t.msgWsDisconnected,
        child: Icon(
          (_containersKey.currentState?.isWsConnected ?? false)
              ? RemixIcon.cloudLine
              : RemixIcon.cloudOffLine,
          color: (_containersKey.currentState?.isWsConnected ?? false)
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }

}
