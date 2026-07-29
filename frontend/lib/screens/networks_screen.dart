import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:intl/intl.dart';
import 'package:mobile_portainer_flutter_module/services/platform/preferences_service.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import '../models/docker_network.dart';
import '../services/docker_service.dart';
import '../widgets/app_search_bar.dart';
import '../widgets/error_view.dart';
import 'package:mobile_portainer_flutter_module/utils/api_error_handler.dart';
import '../widgets/empty_view.dart';
import '../widgets/loading_view.dart';
import '../widgets/layout_toggle.dart';
import 'network_details_screen.dart';

class NetworksScreen extends StatefulWidget {
  final void Function(String networkId, String networkName)? onNetworkSelected;
  final String? selectedNetworkId;

  const NetworksScreen({super.key, this.onNetworkSelected, this.selectedNetworkId});

  @override
  State<NetworksScreen> createState() => NetworksScreenState();
}

class NetworksScreenState extends State<NetworksScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<DockerNetwork> _allNetworks = [];
  List<DockerNetwork> _filteredNetworks = [];
  bool _isLoading = false;
  bool _isCompactMode = false;
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
    _fetchNetworks();
  }

  void refreshAfterSettings() {
    _loadSettingsAndFetch();
  }

  bool get isLoading => _isLoading;
  Future<void> manualRefresh() => _fetchNetworks();
  String get currentApiUrl => _currentApiUrl;
  String get currentApiKey => _currentApiKey;
  bool get currentIgnoreSsl => _currentIgnoreSsl;

  void _onNetworkTap(DockerNetwork network) {
    if (widget.onNetworkSelected != null) {
      widget.onNetworkSelected!(network.id, network.name);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NetworkDetailsScreen(
          networkId: network.id,
          networkName: network.name,
          apiUrl: _currentApiUrl,
          apiKey: _currentApiKey,
          ignoreSsl: _currentIgnoreSsl,
        ),
      ),
    );
  }

  Future<void> _fetchNetworks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final service = DockerService(baseUrl: _currentApiUrl, apiKey: _currentApiKey, ignoreSsl: _currentIgnoreSsl);
    try {
      final networks = await service.getNetworks();
      if (!mounted) return;
      setState(() {
        _allNetworks = networks;
        _filterNetworks();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        ApiErrorHandler.show(context, e);
        _error = e.toString();
        _isLoading = false;
        _allNetworks = [];
        _filteredNetworks = [];
      });
    }
  }

  void _filterNetworks() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredNetworks = _allNetworks.where((network) {
        final name = network.name.toLowerCase();
        final id = network.id.toLowerCase();
        final driver = network.driver.toLowerCase();
        return query.isEmpty || 
               name.contains(query) || 
               id.contains(query) ||
               driver.contains(query);
      }).toList();
    });
  }

  void _onSearchChanged(String query) {
    setState(() {
      _filterNetworks();
    });
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return DateFormat('yyyy-MM-dd HH:mm').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    
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
          hintText: t.hintSearchNetworks,
          onChanged: _onSearchChanged,
          trailing: LayoutToggle(
            isCompactMode: _isCompactMode,
            onToggle: () => setState(() => _isCompactMode = !_isCompactMode),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchNetworks,
            child: _isLoading
                ? const LoadingView(type: LoadingType.list)
                : _filteredNetworks.isEmpty
                  ? const EmptyView(icon: RemixIcon.shareCircleLine, message: '')
                  : ListView.builder(
                    itemCount: _filteredNetworks.length,
                    itemBuilder: (context, index) {
                      final network = _filteredNetworks[index];
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
                            onTap: () => _onNetworkTap(network),
                            title: Text(
                              network.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      }
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _onNetworkTap(network),
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
                                          Text(
                                            network.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'ID: ${network.shortId}',
                                            style: TextStyle(
                                              color: Theme.of(context).textTheme.bodySmall?.color,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    _buildInfoItem(RemixIcon.globalLine, network.driver),
                                    _buildInfoItem(RemixIcon.timeLine, _formatDate(network.created)),
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

  Widget _buildInfoItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
