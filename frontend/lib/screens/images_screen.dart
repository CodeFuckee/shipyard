import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/services/platform/preferences_service.dart';
import 'package:intl/intl.dart';
import '../models/docker_image.dart';
import '../services/docker_service.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/utils/notify_utils.dart';
import '../theme/theme_extensions.dart';
import '../widgets/app_search_bar.dart';
import '../widgets/error_view.dart';
import 'package:mobile_portainer_flutter_module/utils/api_error_handler.dart';
import '../widgets/empty_view.dart';
import '../widgets/loading_view.dart';
import '../widgets/layout_toggle.dart';
import 'image_details_screen.dart';

class ImagesScreen extends StatefulWidget {
  final void Function(String imageId, String imageName)? onImageSelected;
  final String? selectedImageId;

  const ImagesScreen({super.key, this.onImageSelected, this.selectedImageId});

  @override
  State<ImagesScreen> createState() => ImagesScreenState();
}

class ImagesScreenState extends State<ImagesScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<DockerImage> _allImages = [];
  List<DockerImage> _filteredImages = [];
  bool _isLoading = false;
  bool _isGridMode = true;
  String? _error;
  String _currentApiUrl = '';
  String _currentApiKey = '';
  bool _currentIgnoreSsl = false;
  final ScrollController _scrollController = ScrollController();

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
    final isGridMode = prefs.getBool('images_grid_mode') ?? true;
    
    if (mounted) {
      setState(() {
        _currentApiUrl = url;
        _currentApiKey = apiKey;
        _currentIgnoreSsl = ignoreSsl;
        _isGridMode = isGridMode;
      });
    }
    _fetchImages();
  }

  void refreshAfterSettings() {
    _loadSettingsAndFetch();
  }

  bool get isLoading => _isLoading;
  Future<void> manualRefresh() => _fetchImages();
  String get currentApiUrl => _currentApiUrl;
  String get currentApiKey => _currentApiKey;
  bool get currentIgnoreSsl => _currentIgnoreSsl;

  void _onImageTap(DockerImage image, String tags) {
    final targetId = image.id;
    if (widget.onImageSelected != null) {
      widget.onImageSelected!(targetId, tags);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImageDetailsScreen(
          imageId: image.id,
          imageName: tags,
          apiUrl: _currentApiUrl,
          apiKey: _currentApiKey,
          ignoreSsl: _currentIgnoreSsl,
        ),
      ),
    );
  }

  Future<void> _fetchImages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final service = DockerService(baseUrl: _currentApiUrl, apiKey: _currentApiKey, ignoreSsl: _currentIgnoreSsl);
    try {
      final images = await service.getImages();
      if (!mounted) return;
      setState(() {
        _allImages = images;
        _filterImages();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        ApiErrorHandler.show(context, e);
        _error = e.toString();
        _isLoading = false;
        _allImages = [];
        _filteredImages = [];
      });
    }
  }

  void _filterImages() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredImages = _allImages.where((image) {
        final tags = image.repoTags.join(', ').toLowerCase();
        final id = image.id.toLowerCase();
        return query.isEmpty || tags.contains(query) || id.contains(query);
      }).toList();
    });
  }

  void _onSearchChanged(String query) {
    setState(() {
      _filterImages();
    });
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(2)} ${suffixes[i]}';
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
  }

  Future<void> _confirmDelete(DockerImage image) async {
    final t = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.titleConfirmDelete),
        content: Text(t.msgConfirmDeleteImage),
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
      _deleteImage(image);
    }
  }

  Future<void> _deleteImage(DockerImage image) async {
    setState(() {
      _isLoading = true;
    });

    final service = DockerService(
      baseUrl: _currentApiUrl,
      apiKey: _currentApiKey,
      ignoreSsl: _currentIgnoreSsl,
    );
    try {
      final result = image.repoTags.isNotEmpty
          ? await service.deleteImage(image.repoTags.first)
          : await service.deleteImage(image.id);
      
      if (mounted) {
        String message = result['message'] ?? 'Image removed successfully';
        NotifyUtils.showNotify(context, message);
        _fetchImages();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        NotifyUtils.showNotify(context, 'Error: $e');
      }
    }
  }

  Future<void> _toggleLayoutMode() async {
    final prefs = await PreferencesService.getInstance();
    final newMode = !_isGridMode;
    await prefs.setBool('images_grid_mode', newMode);
    if (mounted) {
      setState(() {
        _isGridMode = newMode;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Column(
      children: [
        AppSearchBar(
          controller: _searchController,
          hintText: t.hintSearch,
          onChanged: _onSearchChanged,
          trailing: LayoutToggle(
            isCompactMode: !_isGridMode,
            onToggle: _toggleLayoutMode,
          ),
        ),
        if (_isLoading)
          const Expanded(child: LoadingView(type: LoadingType.list))
        else if (_error != null)
          Expanded(
            child: ErrorView(
              message: _error!,
              subtitle: t.msgCurrentApi(_currentApiUrl),
              onRetry: _fetchImages,
              retryLabel: t.msgRetry,
            ),
          )
        else if (_filteredImages.isEmpty)
           Expanded(
            child: EmptyView(
              icon: RemixIcon.imageLine,
              message: t.msgNoContainers,
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchImages,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 600;
                  
                  if (isWide && _isGridMode) {
                    int crossAxisCount = constraints.maxWidth >= 900 ? 3 : 2;
                    return Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: GridView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          mainAxisExtent: 140,
                        ),
                        itemCount: _filteredImages.length,
                        itemBuilder: (context, index) {
                          final image = _filteredImages[index];
                          final tags = image.repoTags.isNotEmpty ? image.repoTags.join(', ') : '<none>';
                          String shortId = image.id;
                          if (shortId.startsWith('sha256:')) {
                            if (shortId.length > 7) {
                              shortId = shortId.substring(7);
                            }
                          }
                          if (shortId.length > 12) {
                            shortId = shortId.substring(0, 12);
                          }
                          return _buildImageCard(image, tags, shortId, t, margin: EdgeInsets.zero, isGrid: true);
                        },
                      ),
                    );
                  }

                  return Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: ListView.builder(
                      controller: _scrollController,
                      itemCount: _filteredImages.length,
                      itemBuilder: (context, index) {
                        final image = _filteredImages[index];
                        final tags = image.repoTags.isNotEmpty ? image.repoTags.join(', ') : '<none>';
                        String shortId = image.id;
                        if (shortId.startsWith('sha256:')) {
                           if (shortId.length > 7) {
                             shortId = shortId.substring(7);
                           }
                        }
                        if (shortId.length > 12) {
                          shortId = shortId.substring(0, 12);
                        }

                        if (!_isGridMode) {
                          return _buildImageTile(image, tags, shortId, t);
                        }
                        return _buildImageCard(image, tags, shortId, t);
                      },
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImageTile(DockerImage image, String tags, String shortId, AppLocalizations t) {
    final colorScheme = Theme.of(context).colorScheme;
    final dockerColors = Theme.of(context).extension<DockerColors>();

    final tagList = image.repoTags.where((t) => t.isNotEmpty).toList();
    final primaryTag = tagList.isNotEmpty ? tagList.first : '<none>';
    final hasMoreTags = tagList.length > 1;

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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        onTap: () => _onImageTap(image, tags),
        title: Row(
          children: [
            Expanded(
              child: Text(
                primaryTag,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (image.inUse) _buildInUseBadge(dockerColors, t),
          ],
        ),
        subtitle: Row(
          children: [
            if (hasMoreTags) ...[
              Text(
                '+${tagList.length - 1}',
                style: TextStyle(fontSize: 12, color: colorScheme.primary, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 12),
            ],
            Text(
              '${_formatSize(image.size)}  ${_formatDate(image.created)}',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(RemixIcon.deleteBinLine, size: 20, color: colorScheme.error),
          onPressed: () => _confirmDelete(image),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
      ),
    );
  }

  Widget _buildImageCard(DockerImage image, String tags, String shortId, AppLocalizations t, {EdgeInsetsGeometry? margin, bool isGrid = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    final dockerColors = Theme.of(context).extension<DockerColors>();

    final tagList = image.repoTags.where((t) => t.isNotEmpty).toList();
    final primaryTag = tagList.isNotEmpty ? tagList.first : '<none>';
    final hasMoreTags = tagList.length > 1;

    return Card(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () => _onImageTap(image, tags),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      primaryTag,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      maxLines: isGrid ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (image.inUse) _buildInUseBadge(dockerColors, t),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(RemixIcon.deleteBinLine, size: 20, color: colorScheme.error),
                    onPressed: () => _confirmDelete(image),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ],
              ),
              if (hasMoreTags)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    tagList.skip(1).join(', '),
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 10),
              Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildInfoChip(RemixIcon.pieChartLine, _formatSize(image.size), colorScheme),
                  const Spacer(),
                  _buildInfoChip(RemixIcon.timeLine, _formatDate(image.created), colorScheme),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInUseBadge(DockerColors? dockerColors, AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: dockerColors?.inUseBackground ?? const Color(0xFFE8FFEA),
        border: Border.all(color: dockerColors?.inUseBorder ?? const Color(0xFF00B42A), width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        t.labelInUse,
        style: TextStyle(
          color: dockerColors?.inUseBorder ?? const Color(0xFF00B42A),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text, ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
