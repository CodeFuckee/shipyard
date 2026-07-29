import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:intl/intl.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/utils/notify_utils.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../services/docker_service.dart';
import '../models/container_file.dart';
import '../utils/platform_detector.dart';
import '../utils/file_helper.dart';
import '../widgets/error_view.dart';
import 'package:mobile_portainer_flutter_module/utils/api_error_handler.dart';
import '../widgets/loading_view.dart';
import '../theme/theme_extensions.dart';

import 'file_content_screen.dart';

class ContainerFilesScreen extends StatefulWidget {
  final String containerId;
  final String containerName;
  final String apiUrl;
  final String apiKey;
  final bool ignoreSsl;
  final bool isRunning;

  const ContainerFilesScreen({
    super.key,
    required this.containerId,
    required this.containerName,
    required this.apiUrl,
    required this.apiKey,
    this.ignoreSsl = false,
    required this.isRunning,
  });

  @override
  State<ContainerFilesScreen> createState() => _ContainerFilesScreenState();
}

class _ContainerFilesScreenState extends State<ContainerFilesScreen> {
  bool _isLoading = true;
  String? _error;
  List<ContainerFile> _files = [];
  String _currentPath = '/';

  @override
  void initState() {
    super.initState();
    _fetchFiles();
  }

  @override
  void didUpdateWidget(ContainerFilesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRunning != oldWidget.isRunning) {
      _fetchFiles();
    }
  }

  Future<void> _fetchFiles() async {
    if (!widget.isRunning) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _files = [];
    });

    final service = DockerService(
      baseUrl: widget.apiUrl,
      apiKey: widget.apiKey,
      ignoreSsl: widget.ignoreSsl,
    );

    try {
      final files = await service.getContainerFiles(widget.containerId, path: _currentPath);
      // Sort: Directories first, then files. Alphabetically.
      files.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      
      if (!mounted) return;
      setState(() {
        _files = files;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        ApiErrorHandler.show(context, e);
        _isLoading = false;
      });
    }
  }

  Future<void> _openFile(ContainerFile file) async {
    // Construct the full path
    final fullPath = _currentPath == '/' ? '/${file.name}' : '$_currentPath/${file.name}';
    
    setState(() {
      _isLoading = true;
    });

    final service = DockerService(
      baseUrl: widget.apiUrl,
      apiKey: widget.apiKey,
      ignoreSsl: widget.ignoreSsl,
    );

    try {
      final content = await service.getContainerFileContent(widget.containerId, fullPath);
      
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => FileContentScreen(
            containerId: widget.containerId,
            filePath: fullPath,
            initialContent: content,
            apiUrl: widget.apiUrl,
            apiKey: widget.apiKey,
            ignoreSsl: widget.ignoreSsl,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      NotifyUtils.showNotify(context, 'Error reading file: $e');
    }
  }

  Future<void> _shareFile(ContainerFile file) async {
    final t = AppLocalizations.of(context)!;
    final fullPath = _currentPath == '/' ? '/${file.name}' : '$_currentPath/${file.name}';

    setState(() {
      _isLoading = true;
    });

    final service = DockerService(
      baseUrl: widget.apiUrl,
      apiKey: widget.apiKey,
      ignoreSsl: widget.ignoreSsl,
    );

    try {
      final bytes = await service.downloadContainerFile(widget.containerId, fullPath);

      if (!mounted) return;

      if (PlatformDetector.isWeb) {
        await FileHelper.shareBytes(bytes, file.name, text: 'Download ${file.name}');
      } else {
        final tempDirPath = await FileHelper.tempDirPath();
        final filePath = await FileHelper.writeBytes('$tempDirPath/${file.name}', bytes);
        await FileHelper.shareFile(filePath, file.name, text: 'Download ${file.name}');
      }

      setState(() {
        _isLoading = false;
      });

      if (mounted) NotifyUtils.showNotify(context, t.msgFileSaved);

    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        NotifyUtils.showNotify(context, t.msgErrorSavingFile(e.toString()));
      }
    }
  }

  Future<void> _downloadFile(ContainerFile file) async {
    final t = AppLocalizations.of(context)!;
    final fullPath = _currentPath == '/' ? '/${file.name}' : '$_currentPath/${file.name}';

    bool hasPermission = false;
    if (PlatformDetector.isOhos) {
      hasPermission = true;
    } else if (PlatformDetector.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        hasPermission = true;
      } else if (androidInfo.version.sdkInt >= 30) {
        var status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          status = await Permission.manageExternalStorage.request();
        }
        hasPermission = status.isGranted;
      } else {
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
        hasPermission = status.isGranted;
      }
    } else {
      hasPermission = true;
    }

    if (!hasPermission) {
      if (mounted) NotifyUtils.showNotify(context, 'Storage permission denied');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final service = DockerService(
      baseUrl: widget.apiUrl,
      apiKey: widget.apiKey,
      ignoreSsl: widget.ignoreSsl,
    );

    try {
      final bytes = await service.downloadContainerFile(widget.containerId, fullPath);

      if (!mounted) return;

      if (PlatformDetector.isWeb) {
        await FileHelper.triggerDownload(file.name, bytes);
      } else {
        final dirPath = await FileHelper.downloadDirPath();
        if (dirPath == null) {
          throw Exception('Could not find download directory');
        }
        await FileHelper.ensureDir(dirPath);
        final filePath = await FileHelper.writeBytes('$dirPath/${file.name}', bytes);
        if (mounted) NotifyUtils.showNotify(context, '${t.msgFileSaved}: $filePath');
      }

      setState(() {
        _isLoading = false;
      });

      if (mounted && PlatformDetector.isWeb) {
        NotifyUtils.showNotify(context, t.msgFileSaved);
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        NotifyUtils.showNotify(context, t.msgErrorSavingFile(e.toString()));
      }
    }
  }

  void _showFileOptions(ContainerFile file) {
    final t = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(RemixIcon.downloadLine),
                title: Text(t.labelDownload),
                onTap: () {
                  Navigator.pop(context);
                  _downloadFile(file);
                },
              ),
              ListTile(
                leading: const Icon(RemixIcon.shareForwardLine),
                title: Text(t.labelShare),
                onTap: () {
                  Navigator.pop(context);
                  _shareFile(file);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _navigateTo(String directoryName) {
    setState(() {
      if (_currentPath == '/') {
        _currentPath = '/$directoryName';
      } else {
        _currentPath = '$_currentPath/$directoryName';
      }
    });
    _fetchFiles();
  }

  void _navigateUp() {
    if (_currentPath == '/') return;
    
    final parts = _currentPath.split('/');
    if (parts.length <= 2) {
      // empty, "", "dir" -> remove last
      setState(() {
        _currentPath = '/';
      });
    } else {
      parts.removeLast();
      setState(() {
        _currentPath = parts.join('/');
      });
    }
    _fetchFiles();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return _buildBody(t);
  }

  Widget _buildBody(AppLocalizations t) {
    final colorScheme = Theme.of(context).colorScheme;
    if (!widget.isRunning) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(RemixIcon.informationLine, color: colorScheme.onSurfaceVariant, size: 48),
              const SizedBox(height: 16),
              Text(
                t.msgContainerClosed,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: LoadingView(type: LoadingType.list));
    }

    if (_error != null) {
      return ErrorView(
        message: t.msgErrorLoadingFiles,
        subtitle: _error!,
        onRetry: _fetchFiles,
        retryLabel: t.msgRetry,
      );
    }

    return ListView.separated(
      itemCount: _files.length + (_currentPath == '/' ? 0 : 1),
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (_currentPath != '/' && index == 0) {
          return ListTile(
            leading: Icon(RemixIcon.folderLine, color: colorScheme.primary),
            title: const Text('..'),
            onTap: _navigateUp,
          );
        }

        final file = _files[_currentPath == '/' ? index : index - 1];
        return _buildFileItem(file);
      },
    );
  }

  Widget _buildFileItem(ContainerFile file) {
    IconData icon;
    Color iconColor;
    final t = AppLocalizations.of(context)!;
    final dockerColors = Theme.of(context).extension<DockerColors>();

    if (file.isDirectory) {
      icon = RemixIcon.folderLine;
      iconColor = Theme.of(context).colorScheme.primary;
    } else {
      icon = RemixIcon.fileLine;
      iconColor = Theme.of(context).colorScheme.onSurfaceVariant;
    }

    if (file.isSymlink) {
      // Maybe overlay a small arrow or just change icon
      icon = RemixIcon.linkM;
    }

    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Row(
        children: [
          Expanded(child: Text(file.name)),
          if (file.isMounted)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: dockerColors?.mountedBackground ?? const Color(0xFFE8FFEA),
                border: Border.all(color: dockerColors?.mountedBorder ?? const Color(0xFF00B42A)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                t.labelMounted,
                style: TextStyle(
                  color: dockerColors?.mountedBorder ?? const Color(0xFF00B42A),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        '${file.isDirectory ? '-' : _formatSize(file.size)} | ${_formatDate(file.modifiedDate)}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: !file.isDirectory
          ? IconButton(
              icon: const Icon(RemixIcon.more2Fill),
              onPressed: () => _showFileOptions(file),
            )
          : null,
      onTap: file.isDirectory
          ? () => _navigateTo(file.name)
          : () => _openFile(file),
    );
  }
}
