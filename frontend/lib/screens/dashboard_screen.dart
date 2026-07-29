import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/services/platform/preferences_service.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/services/docker_service.dart';
import 'package:mobile_portainer_flutter_module/utils/api_error_handler.dart';
import 'package:mobile_portainer_flutter_module/models/server_usage.dart';
import 'package:intl/intl.dart';
import '../widgets/loading_view.dart';
import '../widgets/empty_view.dart';

class ServerDashboardData {
  final String name;
  final String url;
  final String apiKey;
  final bool ignoreSsl;
  bool isLoading;
  String? error;
  int totalContainers;
  int runningContainers;
  int stoppedContainers;
  int totalImages;
  String? commitDateRaw;
  ServerUsage? usage;
  Timer? retryTimer;
  bool isUsingCache = false;

  ServerDashboardData({
    required this.name,
    required this.url,
    required this.apiKey,
    this.ignoreSsl = false,
    this.isLoading = true,
    this.error,
    this.totalContainers = 0,
    this.runningContainers = 0,
    this.stoppedContainers = 0,
    this.totalImages = 0,
    this.commitDateRaw,
    this.usage,
  });

  void dispose() {
    retryTimer?.cancel();
    retryTimer = null;
  }

  Map<String, dynamic> toCacheJson() {
    return {
      'totalContainers': totalContainers,
      'runningContainers': runningContainers,
      'stoppedContainers': stoppedContainers,
      'totalImages': totalImages,
      'commitDateRaw': commitDateRaw,
      'usage': usage?.toJson(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  void fromCacheJson(Map<String, dynamic> json) {
    totalContainers = json['totalContainers'] ?? 0;
    runningContainers = json['runningContainers'] ?? 0;
    stoppedContainers = json['stoppedContainers'] ?? 0;
    totalImages = json['totalImages'] ?? 0;
    commitDateRaw = json['commitDateRaw'];
    if (json['usage'] != null) {
      try {
        usage = ServerUsage.fromJson(json['usage']);
      } catch (e) {
        debugPrint('Error parsing usage cache: $e');
      }
    }
    // Ensure we don't show loading if we have cache
    isLoading = false;
  }
}

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onSwitchToContainers;
  final VoidCallback? onSwitchToImages;

  const DashboardScreen({
    super.key,
    this.onSwitchToContainers,
    this.onSwitchToImages,
  });

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  List<ServerDashboardData> _serversData = [];
  String _currentApiUrl = '';
  String _timezoneCode = 'system';

  @override
  void initState() {
    super.initState();
    _loadData();
  }


  @override
  void dispose() {
    for (var server in _serversData) {
      server.dispose();
    }
    super.dispose();
  }
  
  // Public method to refresh data (called by MainTabScreen)
  void refresh() {
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _serversData = [];
    });

    final prefs = await PreferencesService.getInstance();
    final serverListJson = prefs.getString('server_list');
    _currentApiUrl = prefs.getString('docker_api_url') ?? '';
    _timezoneCode = prefs.getString('timezone_code') ?? 'system';
    
    List<ServerDashboardData> servers = [];

    if (serverListJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(serverListJson);
        for (var item in decoded) {
          final map = Map<String, String>.from(item);
          if (map.containsKey('url') && map.containsKey('apiKey')) {
            servers.add(ServerDashboardData(
              name: map['name'] ?? 'Unnamed Server',
              url: map['url']!,
              apiKey: map['apiKey']!,
              ignoreSsl: map['ignoreSsl'] == 'true',
            ));
          }
        }
      } catch (e) {
        debugPrint('Error parsing server list: $e');
      }
    }

    // Fallback/Migration: Check for single server config if list is empty
    if (servers.isEmpty) {
      final apiUrl = prefs.getString('docker_api_url');
      final apiKey = prefs.getString('docker_api_key');
      final ignoreSsl = prefs.getString('docker_ignore_ssl') == 'true';
      if (apiUrl != null && apiUrl.isNotEmpty) {
        servers.add(ServerDashboardData(
          name: 'Default Server',
          url: apiUrl,
          apiKey: apiKey ?? '',
          ignoreSsl: ignoreSsl,
        ));
      }
    }

    if (!mounted) return;

    // Load cache for servers
    for (var server in servers) {
      await _loadCache(server);
    }

    setState(() {
      _serversData = servers;
      _isLoading = false;
    });

    // Fetch data for each server independently
    for (var server in _serversData) {
      _fetchServerData(server);
    }
  }

  Future<bool> _loadCache(ServerDashboardData server) async {
    try {
      final prefs = await PreferencesService.getInstance();
      final cacheKey = 'dashboard_cache_${server.url}';
      final jsonStr = prefs.getString(cacheKey);
      if (jsonStr != null) {
        final json = jsonDecode(jsonStr);
        server.fromCacheJson(json);
        return true;
      }
    } catch (e) {
      debugPrint('Error loading cache for ${server.url}: $e');
    }
    return false;
  }

  Future<void> _saveCache(ServerDashboardData server) async {
    try {
      final prefs = await PreferencesService.getInstance();
      final cacheKey = 'dashboard_cache_${server.url}';
      final jsonStr = jsonEncode(server.toCacheJson());
      await prefs.setString(cacheKey, jsonStr);
    } catch (e) {
      debugPrint('Error saving cache for ${server.url}: $e');
    }
  }

  Future<void> _fetchServerData(ServerDashboardData server) async {
    server.retryTimer?.cancel();
    final service = DockerService(baseUrl: server.url, apiKey: server.apiKey, ignoreSsl: server.ignoreSsl);

    try {
      final info = await service.getSystemInfo();

      if (!mounted) return;
      setState(() {
        if (info['docker'] != null && info['docker']['containers'] != null) {
          server.totalContainers = info['docker']['containers']['total'] ?? 0;
          server.runningContainers = info['docker']['containers']['running'] ?? 0;
          server.stoppedContainers = info['docker']['containers']['stopped'] ?? 0;
        } else {
          server.totalContainers = 0;
          server.runningContainers = 0;
          server.stoppedContainers = 0;
        }
        
        server.totalImages = info['docker']?['images'] ?? 0;
        server.commitDateRaw = info['git']?['date']?.toString();
        
        if (info['system'] != null) {
          final cpu = info['system']['cpu'];
          final memory = info['system']['memory'];
          
          if (cpu != null && memory != null) {
            final disks = (info['system']['disk'] as List?)?.map((d) => DiskUsage.fromJson(d)).toList() ?? [];
            final gpus = (info['system']['gpu'] as List?)?.map((g) => GpuUsage.fromJson(g)).toList() ?? [];

            server.usage = ServerUsage(
              cpuPercent: (cpu['percent'] as num).toDouble(),
              cpuCount: (cpu['count'] as num).toInt(),
              memoryPercent: (memory['percent'] as num).toDouble(),
              memoryTotal: (memory['total'] as num).toInt(),
              memoryUsed: (memory['used'] as num).toInt(),
              disks: disks,
              gpus: gpus,
            );
          }
        }
        
        server.isLoading = false;
        server.error = null;
        server.isUsingCache = false;
      });
      _saveCache(server);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // If we have valid data (no error and not loading, or already using cache)
        bool hasData = (!server.isLoading && server.error == null) || server.isUsingCache;
        
        if (hasData) {
          server.isUsingCache = true;
          server.error = null;
        } else {
          ApiErrorHandler.show(context, e);
          server.error = e.toString();
          server.isLoading = false;
        }
      });

      // Retry after 3 seconds
      server.retryTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) _fetchServerData(server);
      });
    }
  }

  Future<void> _switchToAndNavigate(ServerDashboardData server) async {
    final prefs = await PreferencesService.getInstance();
    await prefs.setString('docker_api_url', server.url);
    await prefs.setString('docker_api_key', server.apiKey);
    await prefs.setString('docker_ignore_ssl', server.ignoreSsl.toString());
    
    if (!mounted) return;
    setState(() {
      _currentApiUrl = server.url;
    });

    if (widget.onSwitchToContainers != null) {
      widget.onSwitchToContainers!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    
    return Scaffold(
      body: _isLoading && _serversData.isEmpty
          ? const Center(child: LoadingView(type: LoadingType.card))
          : _serversData.isEmpty
              ? EmptyView(
                  icon: RemixIcon.serverLine,
                  message: t.labelServerInfo,
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Auto mode
                      bool useGrid = constraints.maxWidth >= 600;

                      if (!useGrid) {
                        return ListView.builder(
                          padding: const EdgeInsets.all(16.0),
                          itemCount: _serversData.length,
                          itemBuilder: (context, index) {
                            final server = _serversData[index];
                            return _buildServerCard(context, server, t);
                          },
                        );
                      } else {
                        // Grid Layout
                        // For manual grid mode on small screens, use 1 column or 2 depending on width
                        int crossAxisCount;
                        if (constraints.maxWidth > 900) {
                          crossAxisCount = 3;
                        } else if (constraints.maxWidth >= 600) {
                          crossAxisCount = 2;
                        } else {
                          // Force grid on mobile
                          crossAxisCount = 2; 
                        }
                        
                        double spacing = 16.0;
                        double totalHorizontalPadding = 32.0; // 16 left + 16 right
                        double itemWidth = (constraints.maxWidth - totalHorizontalPadding - (crossAxisCount - 1) * spacing) / crossAxisCount;
                        
                        // Estimate required height for the card to ensure content fits
                        // Header (~80) + Stats (~100) + Usage (~120) + Padding (~40)
                        double itemHeight = 420.0;
                        double childAspectRatio = itemWidth / itemHeight;

                        return GridView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16.0),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: spacing,
                            mainAxisSpacing: spacing,
                            childAspectRatio: childAspectRatio,
                          ),
                          itemCount: _serversData.length,
                          itemBuilder: (context, index) {
                            final server = _serversData[index];
                            return _buildServerCard(context, server, t, margin: EdgeInsets.zero);
                          },
                        );
                      }
                    },
                  ),
                ),
    );
  }

  Widget _buildServerCard(BuildContext context, ServerDashboardData server, AppLocalizations t, {EdgeInsetsGeometry? margin}) {
    final bool isActive = server.url == _currentApiUrl;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: margin ?? const EdgeInsets.only(bottom: 16.0),
      elevation: isActive ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: isActive
            ? BorderSide(color: colorScheme.primary, width: 2)
            : BorderSide(color: colorScheme.outlineVariant, width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.0),
        onTap: () => _switchToAndNavigate(server),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        RemixIcon.serverLine,
                        color: colorScheme.onPrimaryContainer,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  server.name,
                                  style: textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isActive) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Active',
                                    style: textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (_formatDate(server.commitDateRaw).isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  RemixIcon.timeLine,
                                  size: 14,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _formatDate(server.commitDateRaw),
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                if (server.error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(RemixIcon.errorWarningLine, color: colorScheme.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            server.error!,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (server.isLoading)
                  Center(
                    child: CircularProgressIndicator(color: colorScheme.primary),
                  )
                else ...[
                  // Stats Row
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatItem(
                          t.titleContainers,
                          server.totalContainers.toString(),
                          colorScheme.onSurface,
                        ),
                        _buildDivider(),
                        _buildStatItem(
                          t.labelRunning,
                          server.runningContainers.toString(),
                          const Color(0xFF00B42A),
                        ),
                        _buildDivider(),
                        _buildStatItem(
                          t.labelStopped,
                          server.stoppedContainers.toString(),
                          colorScheme.error,
                        ),
                        _buildDivider(),
                        _buildStatItem(
                          t.titleImages,
                          server.totalImages.toString(),
                          colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                  if (server.usage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _buildUsageSection(server.usage!),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 30,
      width: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }

  Widget _buildStatItem(String label, String value, Color valueColor) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      String s = dateStr;
      final tzPattern = RegExp(r'(Z|[+-]\d{2}:\d{2})$');
      if (!tzPattern.hasMatch(s)) {
        s = '${s}Z';
      }
      DateTime date = DateTime.parse(s);
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
    } catch (_) {
      return dateStr;
    }
  }

  Widget _buildUsageSection(ServerUsage usage) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildUsageItem('CPU', usage.cpuPercent),
        const SizedBox(height: 10),
        _buildUsageItem('Memory', usage.memoryPercent,
          subtitle: '${_formatBytes(usage.memoryUsed)} / ${_formatBytes(usage.memoryTotal)}'),
        if (usage.disks.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildUsageItem('Disk', usage.disks.first.percent,
            subtitle: '${_formatBytes(usage.disks.first.used)} / ${_formatBytes(usage.disks.first.total)}'),
        ],
        if (usage.gpus.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...usage.gpus.map((gpu) => Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 Text(gpu.name, style: textTheme.bodySmall?.copyWith(
                   color: colorScheme.onSurface,
                   fontWeight: FontWeight.bold,
                 )),
                 const SizedBox(height: 4),
                 _buildUsageItem('GPU Load (${gpu.temperature.toStringAsFixed(0)}°C)', gpu.load),
                 const SizedBox(height: 4),
                 _buildUsageItem('GPU Memory', (gpu.memoryTotal > 0 ? gpu.memoryUsed / gpu.memoryTotal * 100 : 0),
                     subtitle: '${_formatBytes((gpu.memoryUsed * 1024 * 1024).toInt())} / ${_formatBytes((gpu.memoryTotal * 1024 * 1024).toInt())}'),
              ],
            ),
          )),
        ],
      ],
    );
  }

  Widget _buildUsageItem(String label, double percent, {String? subtitle}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
            Text(subtitle ?? '${percent.toStringAsFixed(1)}%',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              )),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: percent / 100,
          backgroundColor: colorScheme.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation<Color>(
            percent > 80
                ? colorScheme.error
                : (percent > 60 ? const Color(0xFFFF7D00) : colorScheme.primary),
          ),
          minHeight: 4,
          borderRadius: BorderRadius.circular(2),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (bytes > 0) ? (bytes.toString().length - 1) ~/ 3 : 0;
    if (i > 4) i = 4;
    
    double v = bytes / (1 << (10 * i));
    return '${v.toStringAsFixed(1)} ${suffixes[i]}';
  }
}
