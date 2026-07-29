import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/services/platform/preferences_service.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import '../services/docker_service.dart';
import '../widgets/app_search_bar.dart';
import '../widgets/error_view.dart';
import 'package:mobile_portainer_flutter_module/utils/api_error_handler.dart';
import '../widgets/empty_view.dart';
import '../widgets/loading_view.dart';
import '../widgets/layout_toggle.dart';
import 'stack_containers_screen.dart';

class StacksScreen extends StatefulWidget {
  final void Function(String stackName)? onStackSelected;
  final String? selectedStackName;

  const StacksScreen({super.key, this.onStackSelected, this.selectedStackName});

  @override
  State<StacksScreen> createState() => StacksScreenState();
}

class StacksScreenState extends State<StacksScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _allStacks = [];
  List<String> _filteredStacks = [];
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
    _fetchStacks();
  }

  void refreshAfterSettings() {
    _loadSettingsAndFetch();
  }

  bool get isLoading => _isLoading;
  Future<void> manualRefresh() => _fetchStacks();

  void _onStackTap(String stackName) {
    if (widget.onStackSelected != null) {
      widget.onStackSelected!(stackName);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StackContainersScreen(stackName: stackName),
      ),
    );
  }

  Future<void> _fetchStacks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final service = DockerService(baseUrl: _currentApiUrl, apiKey: _currentApiKey, ignoreSsl: _currentIgnoreSsl);
    try {
      final stacks = await service.getStacks();
      if (!mounted) return;
      setState(() {
        _allStacks = stacks;
        _filterStacks();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        ApiErrorHandler.show(context, e);
        _error = e.toString();
        _isLoading = false;
        _allStacks = [];
        _filteredStacks = [];
      });
    }
  }

  void _filterStacks() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredStacks = _allStacks.where((stack) {
        return query.isEmpty || stack.toLowerCase().contains(query);
      }).toList();
    });
  }

  void _onSearchChanged(String query) {
    setState(() {
      _filterStacks();
    });
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
          hintText: t.hintSearchStacks,
          onChanged: _onSearchChanged,
          trailing: LayoutToggle(
            isCompactMode: _isCompactMode,
            onToggle: () => setState(() => _isCompactMode = !_isCompactMode),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchStacks,
            child: _isLoading
                ? const LoadingView(type: LoadingType.list)
                : _filteredStacks.isEmpty
                  ? EmptyView(icon: RemixIcon.appsLine, message: t.msgNoContainers)
                  : ListView.builder(
                    itemCount: _filteredStacks.length,
                    itemBuilder: (context, index) {
                      final stackName = _filteredStacks[index];
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
                            onTap: () => _onStackTap(stackName),
                            title: Text(
                              stackName,
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
                          onTap: () => _onStackTap(stackName),
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
                                            stackName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(RemixIcon.appsLine, color: Theme.of(context).colorScheme.primary.withValues(alpha: .7)),
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
