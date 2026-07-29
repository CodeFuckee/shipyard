import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/services/platform/preferences_service.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/utils/notify_utils.dart';
import '../models/docker_container.dart';
import '../services/docker_service.dart';
import '../theme/theme_extensions.dart';
import '../widgets/app_search_bar.dart';
import '../widgets/error_view.dart';
import 'package:mobile_portainer_flutter_module/utils/api_error_handler.dart';
import '../widgets/empty_view.dart';
import '../widgets/loading_view.dart';
import 'container_details_screen.dart';

class StackContainersScreen extends StatefulWidget {
  final String stackName;
  final VoidCallback? onBack;

  const StackContainersScreen({
    super.key,
    required this.stackName,
    this.onBack,
  });

  @override
  State<StackContainersScreen> createState() => StackContainersScreenState();
}

class StackContainersScreenState extends State<StackContainersScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<DockerContainer> _allContainers = [];
  List<DockerContainer> _filteredContainers = [];
  bool _isLoading = false;
  String? _error;
  String _currentApiUrl = '';
  String _currentApiKey = '';
  bool _currentIgnoreSsl = false;
  bool _isCompactMode = false;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndFetch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSettingsAndFetch() async {
    final prefs = await PreferencesService.getInstance();
    final url = prefs.getString('docker_api_url') ?? 'http://10.0.2.2:2375';
    final apiKey = prefs.getString('docker_api_key') ?? '';
    final ignoreSsl = prefs.getString('docker_ignore_ssl') == 'true';
    if (mounted) {
      setState(() {
        _currentApiUrl = url;
        _currentApiKey = apiKey;
        _currentIgnoreSsl = ignoreSsl;
      });
      _fetchContainers();
    }
  }

  Future<void> _fetchContainers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final service = DockerService(
      baseUrl: _currentApiUrl,
      apiKey: _currentApiKey,
      ignoreSsl: _currentIgnoreSsl,
    );

    try {
      final containers = await service.getStackContainers(widget.stackName);
      
      if (mounted) {
        setState(() {
          _allContainers = containers;
          _filterContainers();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          ApiErrorHandler.show(context, e);
          _error = e.toString();
          _isLoading = false;
          _allContainers = [];
          _filteredContainers = [];
        });
      }
    }
  }

  void _filterContainers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredContainers = _allContainers.where((container) {
        return query.isEmpty || container.name.toLowerCase().contains(query);
      }).toList();
    });
  }

  void _onSearchChanged(String query) {
    _filterContainers();
  }

  Color _getStatusColor(String status) {
    final dockerColors = Theme.of(context).extension<DockerColors>();
    switch (status.toLowerCase()) {
      case 'running':
        return dockerColors?.statusRunning ?? Colors.green;
      case 'exited':
        return dockerColors?.statusExited ?? Colors.red;
      case 'created':
        return dockerColors?.statusCreated ?? Colors.blue;
      case 'restarting':
        return dockerColors?.statusRestarting ?? Colors.orange;
      case 'paused':
        return dockerColors?.statusPaused ?? Colors.amber;
      default:
        return Colors.grey;
    }
  }

  Future<void> _deleteAllContainers() async {
    final t = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.titleConfirmDelete),
        content: Text(t.msgConfirmDeleteAllContainers),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(t.actionDeleteAll),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      final service = DockerService(
        baseUrl: _currentApiUrl,
        apiKey: _currentApiKey,
        ignoreSsl: _currentIgnoreSsl,
      );

      final containersToDelete = List<DockerContainer>.from(_allContainers);
      int successCount = 0;
      int failCount = 0;

      for (final container in containersToDelete) {
        if (container.isSelf) continue;
        
        try {
          await service.removeContainer(container.id, force: true);
          successCount++;
        } catch (e) {
          debugPrint('Failed to delete container ${container.name}: $e');
          failCount++;
        }
      }

      if (mounted) {
        if (failCount > 0) {
          NotifyUtils.showNotify(context, 'Deleted $successCount, Failed $failCount');
        } else {
          NotifyUtils.showNotify(context, '$successCount containers deleted');
        }
        _fetchContainers();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(RemixIcon.arrowLeftLine),
                onPressed: widget.onBack,
              )
            : null,
        title: Text(widget.stackName),
        actions: [
          IconButton(
            icon: Icon(RemixIcon.deleteBinLine, color: Theme.of(context).colorScheme.error),
            onPressed: _allContainers.isEmpty ? null : _deleteAllContainers,
          ),
          IconButton(
            icon: Icon(
              _isCompactMode ? RemixIcon.listView : RemixIcon.listUnordered,
            ),
            onPressed: () {
              setState(() {
                _isCompactMode = !_isCompactMode;
              });
            },
          ),
          IconButton(
            icon: const Icon(RemixIcon.refreshLine),
            onPressed: _fetchContainers,
          ),
        ],
      ),
      body: Column(
        children: [
          AppSearchBar(
            controller: _searchController,
            hintText: t.hintSearch,
            onChanged: _onSearchChanged,
          ),
          if (_isLoading)
            const Expanded(child: LoadingView(type: LoadingType.list))
          else if (_error != null)
            Expanded(
              child: ErrorView(
                message: _error!,
                onRetry: _fetchContainers,
                retryLabel: t.msgRetry,
              ),
            )
          else if (_filteredContainers.isEmpty)
            Expanded(
              child: EmptyView(
                icon: RemixIcon.inboxLine,
                message: t.msgNoContainers,
              ),
            )
          else
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: _filteredContainers.length,
                  itemBuilder: (context, index) {
                    final container = _filteredContainers[index];
                    if (_isCompactMode) {
                      return Container(
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: Theme.of(context).dividerColor,
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 0,
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ContainerDetailsScreen(
                                  containerId: container.id,
                                  containerName: container.name,
                                  apiUrl: _currentApiUrl,
                                  apiKey: _currentApiKey,
                                  ignoreSsl: _currentIgnoreSsl,
                                  isSelf: container.isSelf,
                                ),
                              ),
                            );
                          },
                          title: Text(
                            container.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getStatusColor(
                                container.status,
                              ).withAlpha(30),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _getStatusColor(container.status),
                              ),
                            ),
                            child: Text(
                              container.status.toLowerCase(),
                              style: TextStyle(
                                color: _getStatusColor(container.status),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ContainerDetailsScreen(
                                containerId: container.id,
                                containerName: container.name,
                                apiUrl: _currentApiUrl,
                                apiKey: _currentApiKey,
                                ignoreSsl: _currentIgnoreSsl,
                                isSelf: container.isSelf,
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          container.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _getStatusColor(
                                              container.status,
                                            ).withAlpha(30),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: _getStatusColor(
                                                container.status,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            container.status.toLowerCase(),
                                            style: TextStyle(
                                              color: _getStatusColor(
                                                container.status,
                                              ),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(RemixIcon.arrowRightSLine),
                                ],
                              ),
                              if (container.image.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  container.image,
                                  style: Theme.of(context).textTheme.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              if (container.ports.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  container.ports,
                                  style: Theme.of(context).textTheme.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
