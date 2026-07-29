import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/utils/notify_utils.dart';
import 'images_screen.dart';
import 'networks_screen.dart';
import 'stacks_screen.dart';
import 'volumes_screen.dart';
import 'env_vars_screen.dart';
import 'ports_screen.dart';
import 'package:mobile_portainer_flutter_module/services/platform/preferences_service.dart';
import '../services/docker_service.dart';
import '../theme/app_theme.dart';

class ResourcesScreen extends StatefulWidget {
  final Widget? bottomNavBar;

  const ResourcesScreen({super.key, this.bottomNavBar});

  @override
  State<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends State<ResourcesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final _imagesKey = GlobalKey<ImagesScreenState>();
  final _networksKey = GlobalKey<NetworksScreenState>();
  final _stacksKey = GlobalKey<StacksScreenState>();
  final _volumesKey = GlobalKey<VolumesScreenState>();

  final _tabs = const [
    _TabDef(titleKey: 'titleImages', icon: RemixIcon.stackLine, child: ImagesScreen()),
    _TabDef(titleKey: 'titleNetworks', icon: RemixIcon.shareCircleLine, child: NetworksScreen()),
    _TabDef(titleKey: 'titleStacks', icon: RemixIcon.appsLine, child: StacksScreen()),
    _TabDef(titleKey: 'titleVolumes', icon: RemixIcon.hardDriveLine, child: VolumesScreen()),
    _TabDef(titleKey: 'titleEnvVars', icon: RemixIcon.globalLine, child: EnvVarsScreen()),
    _TabDef(titleKey: 'titlePorts', icon: RemixIcon.plugLine, child: PortsScreen()),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final tabIndex = _tabController.index;

    return Column(
      children: [
        Container(
          color: colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            tabs: _tabs.map((tab) {
              return Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(tab.icon, size: 18),
                    const SizedBox(width: 6),
                    Text(_titleFor(t, tab)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              _buildActiveListScreen(),
              if (widget.bottomNavBar != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: widget.bottomNavBar!,
                ),
              if (tabIndex == 0)
                Positioned(
                  right: 16,
                  bottom: AppTheme.fabBottomInset,
                  child: FloatingActionButton(
                    heroTag: 'fab_pull_image',
                    onPressed: () => _showPullImageDialog(context),
                    child: const Icon(RemixIcon.addLine),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActiveListScreen() {
    final tabIndex = _tabController.index;
    switch (tabIndex) {
      case 0:
        return ImagesScreen(key: _imagesKey);
      case 1:
        return NetworksScreen(key: _networksKey);
      case 2:
        return StacksScreen(key: _stacksKey);
      case 3:
        return VolumesScreen(key: _volumesKey);
      default:
        return _tabs[tabIndex].child;
    }
  }

  String _titleFor(AppLocalizations t, _TabDef tab) {
    switch (tab.titleKey) {
      case 'titleImages': return t.titleImages;
      case 'titleNetworks': return t.titleNetworks;
      case 'titleStacks': return t.titleStacks;
      case 'titleVolumes': return t.titleVolumes;
      case 'titleEnvVars': return t.titleEnvVars;
      case 'titlePorts': return t.titlePorts;
      default: return tab.titleKey;
    }
  }

  Future<void> _showPullImageDialog(BuildContext context) async {
    final t = AppLocalizations.of(context)!;
    final nameController = TextEditingController();
    final tagController = TextEditingController(text: 'latest');

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(t.titlePullImage),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: t.labelImageName,
                  hintText: t.hintImageName,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tagController,
                decoration: InputDecoration(
                  labelText: t.labelTag,
                  hintText: t.hintTag,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t.actionCancel),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final tag = tagController.text.trim().isEmpty
                    ? 'latest'
                    : tagController.text.trim();
                Navigator.pop(dialogContext);
                if (name.isEmpty) {
                  NotifyUtils.showNotify(context, t.msgImageNameRequired);
                  return;
                }

                try {
                  final prefs = await PreferencesService.getInstance();
                  final url =
                      prefs.getString('docker_api_url') ??
                      'http://10.0.2.2:8000';
                  final apiKey = prefs.getString('docker_api_key') ?? '';
                  final ignoreSsl = prefs.getString('docker_ignore_ssl') == 'true';

                  if (!context.mounted) return;

                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => _PullProgressDialog(
                      name: name,
                      tag: tag,
                      baseUrl: url,
                      apiKey: apiKey,
                      ignoreSsl: ignoreSsl,
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  final errMsg = t.msgImagePullFailed(e.toString());
                  NotifyUtils.showNotify(context, errMsg);
                }
              },
              child: Text(t.buttonPull),
            ),
          ],
        );
      },
    );
  }
}

class _TabDef {
  final String titleKey;
  final IconData icon;
  final Widget child;

  const _TabDef({
    required this.titleKey,
    required this.icon,
    required this.child,
  });
}

class _PullProgressDialog extends StatefulWidget {
  final String name;
  final String tag;
  final String baseUrl;
  final String apiKey;
  final bool ignoreSsl;

  const _PullProgressDialog({
    required this.name,
    required this.tag,
    required this.baseUrl,
    required this.apiKey,
    required this.ignoreSsl,
  });

  @override
  State<_PullProgressDialog> createState() => _PullProgressDialogState();
}

class _PullProgressDialogState extends State<_PullProgressDialog> {
  final List<Map<String, String>> _logs = [];
  final ScrollController _scrollController = ScrollController();
  late final DockerService _service;
  late final Stream<dynamic> _stream;
  bool _isDone = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _service = DockerService(
      baseUrl: widget.baseUrl,
      apiKey: widget.apiKey,
      ignoreSsl: widget.ignoreSsl,
    );
    _stream = _service.pullImageWs(widget.name, widget.tag);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(t.titlePullImage),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: StreamBuilder<dynamic>(
          stream: _stream,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final data = snapshot.data;
              String id = '';
              String message = '';

              if (data is Map) {
                if (data.containsKey('error') || data.containsKey('errorDetail')) {
                  message = 'Error: ${data['error'] ?? data['errorDetail']?['message']}';
                  _hasError = true;
                } else {
                  final status = data['status'] ?? '';
                  id = data['id'] ?? '';
                  final progress = data['progress'] ?? '';

                  if (id.isNotEmpty) {
                    message = '$id: $status $progress';
                  } else {
                    message = '$status $progress';
                  }
                }
              } else {
                message = data.toString();
              }

              if (message.trim().isNotEmpty) {
                if (id.isNotEmpty) {
                  final index = _logs.indexWhere((log) => log['id'] == id);
                  if (index != -1) {
                    _logs[index] = {'id': id, 'message': message};
                  } else {
                    _logs.add({'id': id, 'message': message});
                  }
                } else {
                  _logs.add({'id': '', 'message': message});
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                  }
                });
              }
            }

            if (snapshot.connectionState == ConnectionState.done) {
              if (!_isDone) {
                _isDone = true;
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  if (mounted) {
                    setState(() {});
                    if (!_hasError) {
                      await Future.delayed(const Duration(seconds: 1));
                      if (context.mounted) {
                        Navigator.pop(context);
                        if (context.mounted) {
                          NotifyUtils.showNotify(context, t.msgImagePullSuccess);
                        }
                      }
                    }
                  }
                });
              }
            }

            return ListView.builder(
              controller: _scrollController,
              itemCount: _logs.length + (_isDone && !_hasError ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _logs.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      t.msgImagePullSuccess,
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  );
                }
                return Text(_logs[index]['message']!, style: const TextStyle(fontSize: 12));
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.actionCancel),
        ),
      ],
    );
  }
}
