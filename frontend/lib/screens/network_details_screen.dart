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

class NetworkDetailsScreen extends StatefulWidget {
  final String networkId;
  final String networkName;
  final String apiUrl;
  final String apiKey;
  final bool ignoreSsl;
  final VoidCallback? onBack;

  const NetworkDetailsScreen({
    super.key,
    required this.networkId,
    required this.networkName,
    required this.apiUrl,
    required this.apiKey,
    this.ignoreSsl = false,
    this.onBack,
  });

  @override
  State<NetworkDetailsScreen> createState() => _NetworkDetailsScreenState();
}

class _NetworkDetailsScreenState extends State<NetworkDetailsScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _networkDetails;

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
      final details = await service.getNetwork(widget.networkId);
      setState(() {
        _networkDetails = details;
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
        title: Text(widget.networkName),
        actions: [
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

    if (_networkDetails == null) {
      return const Center(child: Text('No details available'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(t),
          if (_networkDetails!['IPAM'] != null && 
              _networkDetails!['IPAM']['Config'] != null && 
              (_networkDetails!['IPAM']['Config'] as List).isNotEmpty)
            _buildIpamCard(t, _networkDetails!['IPAM']['Config']),
          if (_networkDetails!['Labels'] != null && (_networkDetails!['Labels'] as Map).isNotEmpty)
            _buildLabelsCard(t, _networkDetails!['Labels']),
          if (_networkDetails!['Options'] != null && (_networkDetails!['Options'] as Map).isNotEmpty)
            _buildOptionsCard(t, _networkDetails!['Options']),
          if (_networkDetails!['Containers'] != null && (_networkDetails!['Containers'] as Map).isNotEmpty)
            _buildContainersCard(t, _networkDetails!['Containers']),
        ],
      ),
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
            _buildInfoRow(t.labelCreated, _formatDate(_networkDetails!['Created'] ?? '')),
            const Divider(),
            _buildInfoRow('ID', widget.networkId, showCopyButton: true),
            const Divider(),
            _buildInfoRow(t.labelDriver, _networkDetails!['Driver'] ?? ''),
            const Divider(),
            _buildInfoRow(t.labelScope, _networkDetails!['Scope'] ?? ''),
            const Divider(),
            _buildInfoRow(t.labelEnableIPv6, _networkDetails!['EnableIPv6'].toString()),
            const Divider(),
            _buildInfoRow(t.labelInternal, _networkDetails!['Internal'].toString()),
            const Divider(),
            _buildInfoRow(t.labelAttachable, _networkDetails!['Attachable'].toString()),
            const Divider(),
            _buildInfoRow(t.labelIngress, _networkDetails!['Ingress'].toString()),
          ],
        ),
      ),
    );
  }

  Widget _buildIpamCard(AppLocalizations t, List<dynamic> config) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(t.labelIPAM, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: config.map((cfg) {
                return Column(
                  children: [
                    if (cfg['Subnet'] != null)
                      _buildInfoRow(t.labelSubnet, cfg['Subnet']),
                    if (cfg['Gateway'] != null) ...[
                      const SizedBox(height: 8),
                      _buildInfoRow(t.labelGateway, cfg['Gateway']),
                    ],
                    if (config.indexOf(cfg) < config.length - 1)
                      const Divider(),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLabelsCard(AppLocalizations t, Map<String, dynamic> labels) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
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

  Widget _buildContainersCard(AppLocalizations t, Map<String, dynamic> containers) {
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
              children: containers.entries.map((entry) {
                final containerId = entry.key;
                final containerData = entry.value as Map<String, dynamic>;
                final containerName = containerData['Name'] ?? containerId;
                
                return InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ContainerDetailsScreen(
                          containerId: containerId,
                          containerName: containerName,
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                containerName,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Theme.of(context).colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                              if (containerData['IPv4Address'] != null && containerData['IPv4Address'].isNotEmpty)
                                Text(
                                  containerData['IPv4Address'],
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).textTheme.bodySmall?.color,
                                  ),
                                ),
                            ],
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

  Widget _buildInfoRow(String label, String value, {bool showCopyButton = false, bool isMonospace = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    value,
                    style: TextStyle(
                      fontFamily: isMonospace ? 'monospace' : null,
                    ),
                  ),
                ),
                if (showCopyButton)
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: value));
                      NotifyUtils.showNotify(context, 'Copied $label to clipboard');
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Icon(RemixIcon.fileCopyLine, size: 16),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      // Handle timestamp that might be in a different format
      // Docker usually returns ISO 8601
      return dateStr.substring(0, 19).replaceAll('T', ' ');
    } catch (_) {
      return dateStr;
    }
  }
}
