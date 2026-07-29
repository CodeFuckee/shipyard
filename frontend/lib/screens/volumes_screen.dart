import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/services/platform/preferences_service.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import '../services/docker_service.dart';
import '../models/docker_volume.dart';
import '../theme/theme_extensions.dart';
import '../widgets/app_search_bar.dart';
import '../widgets/error_view.dart';
import 'package:mobile_portainer_flutter_module/utils/api_error_handler.dart';
import '../widgets/empty_view.dart';
import '../widgets/loading_view.dart';
import '../widgets/layout_toggle.dart';
import 'volume_details_screen.dart';
import '../utils/notify_utils.dart';

enum VolumeFilter { all, inUse, unused }

class VolumesScreen extends StatefulWidget {
  final void Function(String volumeName)? onVolumeSelected;
  final String? selectedVolumeName;

  const VolumesScreen({super.key, this.onVolumeSelected, this.selectedVolumeName});

  @override
  State<VolumesScreen> createState() => VolumesScreenState();
}

class VolumesScreenState extends State<VolumesScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<DockerVolume> _allVolumes = [];
  List<DockerVolume> _filteredVolumes = [];
  bool _isLoading = false;
  bool _isCompactMode = false;
  VolumeFilter _currentFilter = VolumeFilter.all;
  String? _error;
  String _currentApiUrl = '';
  String _currentApiKey = '';
  bool _currentIgnoreSsl = false;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndFetch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSettingsAndFetch() async {
    final prefs = await PreferencesService.getInstance();
    final url = prefs.getString('docker_api_url') ?? 'http://10.0.2.2:2375';
    final apiKey = prefs.getString('docker_api_key') ?? '';
    final ignoreSsl = prefs.getString('docker_ignore_ssl') == 'true';
    setState(() {
      _currentApiUrl = url;
      _currentApiKey = apiKey;
      _currentIgnoreSsl = ignoreSsl;
    });
    _fetchVolumes();
  }

  void refreshAfterSettings() {
    _loadSettingsAndFetch();
  }

  bool get isLoading => _isLoading;
  Future<void> manualRefresh() => _fetchVolumes();
  String get currentApiUrl => _currentApiUrl;
  String get currentApiKey => _currentApiKey;
  bool get currentIgnoreSsl => _currentIgnoreSsl;

  void _onVolumeTap(DockerVolume volume) {
    if (widget.onVolumeSelected != null) {
      widget.onVolumeSelected!(volume.name);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VolumeDetailsScreen(
          volumeName: volume.name,
          apiUrl: _currentApiUrl,
          apiKey: _currentApiKey,
          ignoreSsl: _currentIgnoreSsl,
        ),
      ),
    ).then((result) {
      if (result == true) _fetchVolumes();
    });
  }

  Future<void> _fetchVolumes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final service = DockerService(baseUrl: _currentApiUrl, apiKey: _currentApiKey, ignoreSsl: _currentIgnoreSsl);
    try {
      final volumes = await service.getVolumes();
      if (!mounted) return;
      setState(() {
        _allVolumes = volumes;
        _filterVolumes();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        ApiErrorHandler.show(context, e);
        _error = e.toString();
        _isLoading = false;
        _allVolumes = [];
        _filteredVolumes = [];
      });
    }
  }

  void _filterVolumes() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredVolumes = _allVolumes.where((volume) {
        final matchesQuery = query.isEmpty || volume.name.toLowerCase().contains(query);
        final matchesFilter = switch (_currentFilter) {
          VolumeFilter.all => true,
          VolumeFilter.inUse => volume.inUse,
          VolumeFilter.unused => !volume.inUse,
        };
        return matchesQuery && matchesFilter;
      }).toList();
    });
  }

  void _onSearchChanged(String query) {
    setState(() {
      _filterVolumes();
    });
  }

  Future<void> _deleteVolume(DockerVolume volume) async {
    final t = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.titleConfirmDelete),
        content: Text(t.msgConfirmDeleteVolume),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: Text(t.actionDelete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      final service = DockerService(baseUrl: _currentApiUrl, apiKey: _currentApiKey, ignoreSsl: _currentIgnoreSsl);
      try {
        await service.deleteVolume(volume.name);
        if (mounted) {
          NotifyUtils.showNotify(context, t.msgVolumeDeleted);
          _fetchVolumes();
        }
      } catch (e) {
        if (mounted) {
          NotifyUtils.showNotify(context, t.msgDeleteVolumeFailed(e.toString()));
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    
    final colorScheme = Theme.of(context).colorScheme;
    final dockerColors = Theme.of(context).extension<DockerColors>();

    if (_error != null) {
      return ErrorView(
        message: _error!,
        subtitle: t.msgCurrentApi(_currentApiUrl),
        onRetry: _loadSettingsAndFetch,
        retryLabel: t.msgRetry,
      );
    }

    return Column(
      children: [
        AppSearchBar(
          controller: _searchController,
          hintText: t.hintSearchVolumes,
          onChanged: _onSearchChanged,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                child: PopupMenuButton<VolumeFilter>(
                  tooltip: t.filterAll,
                  onSelected: (VolumeFilter item) {
                    setState(() {
                      _currentFilter = item;
                      _filterVolumes();
                    });
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<VolumeFilter>>[
                    PopupMenuItem<VolumeFilter>(
                      value: VolumeFilter.all,
                      child: Text(t.filterAll),
                    ),
                    PopupMenuItem<VolumeFilter>(
                      value: VolumeFilter.inUse,
                      child: Text(t.filterInUse),
                    ),
                    PopupMenuItem<VolumeFilter>(
                      value: VolumeFilter.unused,
                      child: Text(t.filterUnused),
                    ),
                  ],
                  child: Container(
                    width: 50,
                    height: 50,
                    alignment: Alignment.center,
                    child: Icon(
                      RemixIcon.filterLine,
                      color: _currentFilter != VolumeFilter.all
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              LayoutToggle(
                isCompactMode: _isCompactMode,
                onToggle: () => setState(() => _isCompactMode = !_isCompactMode),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchVolumes,
            child: _isLoading
                ? const LoadingView(type: LoadingType.list)
                : _filteredVolumes.isEmpty
                  ? EmptyView(icon: RemixIcon.hardDriveLine, message: t.msgNoContainers)
                  : ListView.builder(
                    itemCount: _filteredVolumes.length,
                    itemBuilder: (context, index) {
                      final volume = _filteredVolumes[index];
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
                            onTap: () => _onVolumeTap(volume),
                            title: Text(
                              volume.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (volume.inUse)
                                  Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: dockerColors?.inUseBackground ?? const Color(0xFFE8FFEA),
                                      border: Border.all(color: dockerColors?.inUseBorder ?? const Color(0xFF00B42A)),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      t.labelInUse,
                                      style: TextStyle(
                                        color: dockerColors?.inUseBorder ?? const Color(0xFF00B42A),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withValues(alpha: .1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                      volume.driver,
                                      style: TextStyle(
                                        color: colorScheme.primary,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(RemixIcon.deleteBinLine, size: 20, color: colorScheme.onSurfaceVariant),
                                    onPressed: () => _deleteVolume(volume),
                                    tooltip: t.actionDelete,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _onVolumeTap(volume),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  volume.name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                              if (volume.inUse)
                                                Container(
                                                  margin: const EdgeInsets.only(left: 8),
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: dockerColors?.inUseBackground ?? const Color(0xFFE8FFEA),
                                                    border: Border.all(color: dockerColors?.inUseBorder ?? const Color(0xFF00B42A)),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    t.labelInUse,
                                                    style: TextStyle(
                                                      color: dockerColors?.inUseBorder ?? const Color(0xFF00B42A),
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              IconButton(
                                                icon: Icon(RemixIcon.deleteBinLine, size: 20, color: colorScheme.onSurfaceVariant),
                                                onPressed: () => _deleteVolume(volume),
                                                tooltip: t.actionDelete,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${t.labelDriver}: ${volume.driver}',
                                            style: TextStyle(
                                              color: colorScheme.onSurfaceVariant,
                                              fontSize: 12,
                                            ),
                                          ),
                                          if (volume.mountpoint.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              volume.mountpoint,
                                              style: TextStyle(
                                                color: colorScheme.onSurfaceVariant,
                                                fontSize: 12,
                                                fontFamily: 'Monospace'
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ],
                                          if (volume.created.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              volume.created,
                                              style: TextStyle(
                                                color: colorScheme.onSurfaceVariant,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
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
    );
  }
}
