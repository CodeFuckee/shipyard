import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/services/platform/preferences_service.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import '../services/docker_service.dart';
import '../widgets/error_view.dart';
import 'package:mobile_portainer_flutter_module/utils/api_error_handler.dart';
import '../widgets/loading_view.dart';

class PortsScreen extends StatefulWidget {
  const PortsScreen({super.key});

  @override
  State<PortsScreen> createState() => _PortsScreenState();
}

class _PortsScreenState extends State<PortsScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _portsData;
  String _currentApiUrl = '';
  String _currentApiKey = '';
  bool _currentIgnoreSsl = false;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndFetch();
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
      _fetchPorts();
    }
  }

  Future<void> _fetchPorts() async {
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
      final data = await service.getAvailablePorts();
      if (mounted) {
        setState(() {
          _portsData = data;
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
    final t = AppLocalizations.of(context)!;

    if (_isLoading) {
      return const Center(child: LoadingView(type: LoadingType.card));
    }

    if (_error != null) {
      return ErrorView(
        message: _error!,
        onRetry: _fetchPorts,
        retryLabel: t.msgRetry,
      );
    }

    if (_portsData == null) {
      return const Center(child: Text('No data'));
    }

    final totalAvailable = _portsData!['total_available'] as int? ?? 0;
    final ranges = (_portsData!['ranges'] as List<dynamic>?)?.cast<String>() ?? [];

    return Column(
      children: [
        Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  t.msgAvailablePorts(totalAvailable),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Icon(RemixIcon.checkboxCircleLine, color: Colors.green),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: ranges.length,
            itemBuilder: (context, index) {
              final range = ranges[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: const Icon(RemixIcon.arrowLeftRightLine),
                  title: Text(range),
                  subtitle: Text(t.msgPortRange),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
