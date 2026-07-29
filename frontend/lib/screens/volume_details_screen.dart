import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:flutter/services.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import '../services/docker_service.dart';
import '../utils/notify_utils.dart';
import '../widgets/error_view.dart';
import 'package:mobile_portainer_flutter_module/utils/api_error_handler.dart';
import '../widgets/loading_view.dart';

import 'container_details_screen.dart';

class VolumeDetailsScreen extends StatefulWidget {
  final String volumeName;
  final String apiUrl;
  final String apiKey;
  final bool ignoreSsl;
  final VoidCallback? onBack;

  const VolumeDetailsScreen({
    super.key,
    required this.volumeName,
    required this.apiUrl,
    required this.apiKey,
    this.ignoreSsl = false,
    this.onBack,
  });

  @override
  State<VolumeDetailsScreen> createState() => _VolumeDetailsScreenState();
}

class _VolumeDetailsScreenState extends State<VolumeDetailsScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _volumeDetails;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final service = DockerService(baseUrl: widget.apiUrl, apiKey: widget.apiKey, ignoreSsl: widget.ignoreSsl);
    try {
      final details = await service.getVolume(widget.volumeName);
      setState(() {
        _volumeDetails = details;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        ApiErrorHandler.show(context, e);
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteVolume() async {
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

      final service = DockerService(baseUrl: widget.apiUrl, apiKey: widget.apiKey, ignoreSsl: widget.ignoreSsl);
      try {
        await service.deleteVolume(widget.volumeName);
        if (mounted) {
          NotifyUtils.showNotify(context, t.msgVolumeDeleted);
          Navigator.pop(context, true); // Return true to indicate deletion
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

    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(RemixIcon.arrowLeftLine),
                onPressed: widget.onBack,
              )
            : null,
        title: Text(widget.volumeName),
        actions: [
          IconButton(
            icon: const Icon(RemixIcon.deleteBinLine),
            onPressed: _deleteVolume,
            tooltip: t.actionDelete,
          ),
          IconButton(
            icon: const Icon(RemixIcon.refreshLine),
            onPressed: _fetchDetails,
          ),
        ],
      ),
      body: _buildBody(t),
    );
  }

  Widget _buildBody(AppLocalizations t) {
    if (_isLoading) {
      return const LoadingView(type: LoadingType.card);
    }

    if (_error != null) {
      return ErrorView(
        message: _error!,
        subtitle: t.msgCurrentApi(widget.apiUrl),
        onRetry: _fetchDetails,
        retryLabel: t.msgRetry,
      );
    }

    if (_volumeDetails == null) {
      return const Center(child: Text('No details available'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(t),
          const SizedBox(height: 16),
          if (_volumeDetails!['Labels'] != null && (_volumeDetails!['Labels'] as Map).isNotEmpty)
            _buildLabelsCard(t, _volumeDetails!['Labels']),
          if (_volumeDetails!['Options'] != null && (_volumeDetails!['Options'] as Map).isNotEmpty)
            _buildOptionsCard(t, _volumeDetails!['Options']),
          if (_volumeDetails!['used_by_containers'] != null && (_volumeDetails!['used_by_containers'] as List).isNotEmpty)
            _buildContainersCard(t, _volumeDetails!['used_by_containers']),
        ],
      ),
    );
  }

  Widget _buildContainersCard(AppLocalizations t, List<dynamic> containers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(t.labelUsedByContainers, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: containers.map((container) {
                return InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ContainerDetailsScreen(
                          containerId: container.toString(),
                          containerName: container.toString(),
                          apiUrl: widget.apiUrl,
                          apiKey: widget.apiKey,
                          ignoreSsl: widget.ignoreSsl,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        Icon(RemixIcon.box3Line, size: 16, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            container.toString(),
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        Icon(RemixIcon.arrowRightSLine, size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(AppLocalizations t) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('ID', widget.volumeName, showCopyButton: true),
            const Divider(),
            _buildInfoRow(t.labelDriver, _volumeDetails!['Driver'] ?? ''),
            const Divider(),
            _buildInfoRow(t.labelScope, _volumeDetails!['Scope'] ?? ''),
            const Divider(),
            _buildInfoRow(t.labelCreated, _volumeDetails!['CreatedAt'] ?? ''),
            const Divider(),
            _buildInfoRow(t.labelMountpoint, _volumeDetails!['Mountpoint'] ?? '', isMonospace: true),
          ],
        ),
      ),
    );
  }

  Widget _buildLabelsCard(AppLocalizations t, Map<String, dynamic> labels) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.labelLabels, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: labels.entries.map((e) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: SelectableText(e.value.toString()),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionsCard(AppLocalizations t, Map<String, dynamic> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(t.labelOptions, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: options.entries.map((e) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: SelectableText(e.value.toString()),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isMonospace = false, bool showCopyButton = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: value));
                NotifyUtils.showNotify(context, '$label copied');
              },
              child: Text(
                value,
                style: TextStyle(
                  fontFamily: isMonospace ? 'monospace' : null,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          if (showCopyButton)
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                NotifyUtils.showNotify(context, '$label copied');
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Icon(RemixIcon.fileCopyLine, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}
