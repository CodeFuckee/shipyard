import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/services/platform/preferences_service.dart';
import '../services/docker_service.dart';
import 'package:intl/intl.dart';
import '../theme/theme_extensions.dart';
import '../widgets/section_title.dart';
import '../widgets/info_card.dart';
import '../widgets/info_row.dart';
import '../widgets/error_view.dart';
import 'package:mobile_portainer_flutter_module/utils/api_error_handler.dart';
import '../widgets/loading_view.dart';

class ImageDetailsScreen extends StatefulWidget {
  final String imageId;
  final String imageName;
  final String apiUrl;
  final String apiKey;
  final bool ignoreSsl;
  final VoidCallback? onBack;

  const ImageDetailsScreen({
    super.key,
    required this.imageId,
    required this.imageName,
    required this.apiUrl,
    required this.apiKey,
    this.ignoreSsl = false,
    this.onBack,
  });

  @override
  State<ImageDetailsScreen> createState() => _ImageDetailsScreenState();
}

class _ImageDetailsScreenState extends State<ImageDetailsScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _imageDetails;
  String _timezoneCode = 'system';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _fetchDetails();
  }

  Future<void> _loadPreferences() async {
    final prefs = await PreferencesService.getInstance();
    if (mounted) {
      setState(() {
        _timezoneCode = prefs.getString('timezone_code') ?? 'system';
      });
    }
  }

  Future<void> _fetchDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final service = DockerService(baseUrl: widget.apiUrl, apiKey: widget.apiKey, ignoreSsl: widget.ignoreSsl);
    try {
      final details = await service.getImage(widget.imageId);
      if (mounted) {
        setState(() {
          _imageDetails = details;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          ApiErrorHandler.show(context, e);
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(RemixIcon.arrowLeftLine),
                onPressed: widget.onBack,
              )
            : null,
        title: Text(widget.imageName, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(RemixIcon.refreshLine),
            onPressed: _fetchDetails,
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingView(type: LoadingType.card)
          : _error != null
              ? ErrorView(
                  message: _error!,
                  onRetry: _fetchDetails,
                  retryLabel: 'Retry',
                )
              : _buildDetailsList(),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    if (dateStr == '0001-01-01T00:00:00Z') return '';
    try {
      DateTime date = DateTime.parse(dateStr);

      // Apply timezone adjustment
      switch (_timezoneCode) {
        case 'utc':
          date = date.toUtc();
          break;
        case 'utc+8':
          date = date.toUtc().add(const Duration(hours: 8));
          break;
        case 'utc+9':
          date = date.toUtc().add(const Duration(hours: 9));
          break;
        case 'utc-5':
          date = date.toUtc().subtract(const Duration(hours: 5));
          break;
        case 'utc+1':
          date = date.toUtc().add(const Duration(hours: 1));
          break;
        case 'system':
        default:
          date = date.toLocal();
          break;
      }

      return DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  String _formatSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '0 B';
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(2)} ${suffixes[i]}';
  }

  Widget _buildDetailsList() {
    if (_imageDetails == null) return const SizedBox();

    final details = _imageDetails!;
    final config = details['Config'] ?? {};
    final rootFS = details['RootFS'] ?? {};
    final layers = rootFS['Layers'] as List? ?? [];
    final accentColor = DockerResourceIconColor.images;
    final shortId = (details['Id']?.toString() ?? '').replaceFirst('sha256:', '').substring(0, 12);

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildSummaryCard(details, shortId, accentColor),
        const SizedBox(height: 20),
        _buildSectionTitle('Basic Info'),
        _buildInfoCard([
          _buildInfoRow('ID', details['Id']?.toString().substring(7, 19) ?? '', showCopyButton: true), // Short ID
          _buildInfoRow('Full ID', details['Id']?.toString() ?? '', showCopyButton: true),
          _buildInfoRow('Size', _formatSize(details['Size'])),
          _buildInfoRow('Created', _formatDate(details['Created'])),
          _buildInfoRow('OS/Arch', '${details['Os']}/${details['Architecture']}'),
          _buildInfoRow('Docker Version', details['DockerVersion'] ?? ''),
          _buildInfoRow('Author', details['Author'] ?? ''),
        ]),
        const SizedBox(height: 16),

        if (details['RepoTags'] != null && (details['RepoTags'] as List).isNotEmpty) ...[
          _buildSectionTitle('Tags'),
          _buildListCard(details['RepoTags']),
          const SizedBox(height: 16),
        ],

        _buildSectionTitle('Config'),
        _buildInfoCard([
          _buildInfoRow('User', config['User'] ?? ''),
          _buildInfoRow('WorkingDir', config['WorkingDir'] ?? ''),
          _buildInfoRow('Entrypoint', (config['Entrypoint'] as List?)?.join(' ') ?? ''),
          _buildInfoRow('Cmd', (config['Cmd'] as List?)?.join(' ') ?? ''),
        ]),
        const SizedBox(height: 16),

        if (config['Env'] != null && (config['Env'] as List).isNotEmpty) ...[
          _buildSectionTitle('Environment Variables'),
          _buildEnvCard(config['Env']),
          const SizedBox(height: 16),
        ],

        if (config['Volumes'] != null && (config['Volumes'] as Map).isNotEmpty) ...[
          _buildSectionTitle('Volumes'),
          _buildMapCard(config['Volumes']),
          const SizedBox(height: 16),
        ],
        
        if (config['ExposedPorts'] != null && (config['ExposedPorts'] as Map).isNotEmpty) ...[
          _buildSectionTitle('Exposed Ports'),
          _buildMapCard(config['ExposedPorts']),
          const SizedBox(height: 16),
        ],

        if (config['Labels'] != null && (config['Labels'] as Map).isNotEmpty) ...[
          _buildSectionTitle('Labels'),
          _buildLabelsCard(config['Labels']),
          const SizedBox(height: 16),
        ],

        _buildSectionTitle('Layers (${layers.length})'),
        _buildListCard(layers.map((l) => l.toString()).toList(), monospace: true),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic> details, String shortId, Color accentColor) {
    final colorScheme = Theme.of(context).colorScheme;
    final tags = details['RepoTags'] as List?;
    final primaryTag = (tags != null && tags.isNotEmpty) ? tags.first.toString() : widget.imageName;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Container(height: 4, color: accentColor),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(RemixIcon.archiveLine, color: accentColor, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            primaryTag,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'ID: $shortId',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildStatItem(RemixIcon.pieChartLine, _formatSize(details['Size']), 'Size', colorScheme),
                    _buildStatItem(RemixIcon.timeLine, _formatDate(details['Created']), 'Created', colorScheme),
                    _buildStatItem(RemixIcon.cpuLine, '${details['Os']}/${details['Architecture']}', 'OS/Arch', colorScheme),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label, ColorScheme colorScheme) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return SectionTitle(title: title);
  }

  Widget _buildInfoCard(List<Widget> children) {
    return InfoCard(children: children);
  }

  Widget _buildInfoRow(String label, String value, {bool showCopyButton = false}) {
    if (value.isEmpty) return const SizedBox.shrink();
    return InfoRow(
      label: label,
      value: value,
      showCopyButton: showCopyButton,
    );
  }

  Widget _buildListCard(List<dynamic> items, {bool monospace = false}) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items.asMap().entries.map((entry) {
            final isLast = entry.key == items.length - 1;
            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: SelectableText(
                entry.value.toString(),
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: monospace ? 'monospace' : null,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEnvCard(List<dynamic> envs) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: envs.asMap().entries.map((entry) {
            final env = entry.value.toString();
            final parts = env.split('=');
            final key = parts.isNotEmpty ? parts[0] : '';
            final value = parts.length > 1 ? parts.sublist(1).join('=') : '';
            final isLast = entry.key == envs.length - 1;
            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(key, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  SelectableText(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildMapCard(Map<String, dynamic> map) {
    final entries = map.entries.toList();
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: entries.asMap().entries.map((e) {
            final key = e.value.key;
            final value = e.value.value;
            final isLast = e.key == entries.length - 1;
            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  if (value != null && value.toString() != '{}')
                    SelectableText(value.toString(), style: const TextStyle(fontSize: 13)),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildLabelsCard(Map<String, dynamic> labels) {
    final entries = labels.entries.toList();
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: entries.asMap().entries.map((e) {
            final key = e.value.key;
            final value = e.value.value;
            final isLast = e.key == entries.length - 1;
            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(key, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  SelectableText(value.toString(), style: const TextStyle(fontSize: 13)),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
