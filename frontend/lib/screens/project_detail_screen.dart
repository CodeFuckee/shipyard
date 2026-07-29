import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/utils/api_error_handler.dart';
import '../services/docker_service.dart';
import '../models/build_log.dart';
import '../widgets/code_editor.dart';
import '../widgets/build_log_view.dart';
import '../widgets/loading_view.dart';
import '../widgets/error_view.dart';

class ProjectDetailScreen extends StatefulWidget {
  final String projectId;
  final String projectName;
  final String apiUrl;
  final String apiKey;
  final bool ignoreSsl;

  const ProjectDetailScreen({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.apiUrl,
    required this.apiKey,
    this.ignoreSsl = false,
  });

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;

  // 文件内容
  String _dockerfileContent = '';
  String _composeContent = '';
  bool _isLoadingFiles = true;
  String? _loadError;

  // 原始内容（用于判断是否有未保存修改）
  String _originalDockerfileContent = '';
  String _originalComposeContent = '';

  // 项目状态
  String _projectStatus = 'idle';

  // 构建相关
  StreamController<BuildLog>? _buildLogController;
  Stream<BuildLog>? _buildLogStream;
  bool _isBuilding = false;
  bool _showBuildLog = false;

  DockerService get _service => DockerService(
        baseUrl: widget.apiUrl,
        apiKey: widget.apiKey,
        ignoreSsl: widget.ignoreSsl,
      );

  bool get _hasUnsavedChanges =>
      _dockerfileContent != _originalDockerfileContent ||
      _composeContent != _originalComposeContent;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _buildLogController?.close();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadProjectInfo(),
      _loadFiles(),
    ]);
  }

  Future<void> _loadProjectInfo() async {
    try {
      final project = await _service.getProject(widget.projectId);
      if (!mounted) return;
      setState(() {
        _projectStatus = project.status;
      });
    } catch (e) {
      if (!mounted) return;
    }
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoadingFiles = true;
      _loadError = null;
    });

    try {
      final results = await Future.wait([
        _service.getProjectFile(widget.projectId, 'Dockerfile'),
        _service.getProjectFile(widget.projectId, 'docker-compose.yaml'),
      ]);

      if (!mounted) return;
      setState(() {
        _dockerfileContent = results[0];
        _composeContent = results[1];
        _originalDockerfileContent = results[0];
        _originalComposeContent = results[1];
        _isLoadingFiles = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _isLoadingFiles = false;
      });
    }
  }

  Future<void> _saveAll() async {
    final t = AppLocalizations.of(context)!;
    try {
      await Future.wait([
        _service.updateProjectFile(
            widget.projectId, 'Dockerfile', _dockerfileContent),
        _service.updateProjectFile(
            widget.projectId, 'docker-compose.yaml', _composeContent),
      ]);
      if (!mounted) return;
      setState(() {
        _originalDockerfileContent = _dockerfileContent;
        _originalComposeContent = _composeContent;
      });
      ApiErrorHandler.show(context, t.msgSaveAll);
    } catch (e) {
      if (!mounted) return;
      ApiErrorHandler.handle(context, e);
    }
  }

  Future<void> _triggerBuild() async {
    final t = AppLocalizations.of(context)!;

    if (_hasUnsavedChanges) {
      ApiErrorHandler.show(context, t.msgSaveBeforeBuild);
      return;
    }

    if (_dockerfileContent.trim().isEmpty) {
      ApiErrorHandler.show(context, t.msgSaveBeforeBuild);
      return;
    }

    setState(() {
      _isBuilding = true;
      _showBuildLog = true;
    });

    // 关闭旧的 stream controller
    _buildLogController?.close();
    _buildLogController = StreamController<BuildLog>.broadcast();

    try {
      await _service.triggerBuild(widget.projectId);
      if (!mounted) return;

      _buildLogStream = _service.getBuildLogs(widget.projectId);
      _buildLogStream!.listen(
        (log) {
          _buildLogController?.add(log);
        },
        onError: (error) {
          _buildLogController?.add(BuildLog(error: error.toString(), isDone: true));
        },
        onDone: () {
          _buildLogController?.close();
          if (mounted) {
            setState(() {
              _isBuilding = false;
            });
            _loadProjectInfo();
          }
        },
      );
      ApiErrorHandler.show(context, t.msgBuildStarted);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBuilding = false;
      });
      ApiErrorHandler.handle(context, e);
    }
  }

  Future<void> _triggerUp() async {
    final t = AppLocalizations.of(context)!;
    try {
      final result = await _service.triggerProjectUp(widget.projectId);
      if (!mounted) return;
      setState(() {
        _projectStatus = 'running';
      });
      final containerIds = result['containerIds'] ?? result['container_ids'] ?? [];
      ApiErrorHandler.show(
        context,
        '${t.msgComposeUpSuccess}${containerIds.isNotEmpty ? ': $containerIds' : ''}',
      );
    } catch (e) {
      if (!mounted) return;
      ApiErrorHandler.handle(context, e);
    }
  }

  Future<void> _triggerDown() async {
    final t = AppLocalizations.of(context)!;
    try {
      await _service.triggerProjectDown(widget.projectId);
      if (!mounted) return;
      setState(() {
        _projectStatus = 'idle';
      });
      ApiErrorHandler.show(context, t.msgComposeDownSuccess);
    } catch (e) {
      if (!mounted) return;
      ApiErrorHandler.handle(context, e);
    }
  }

  Future<bool> _onWillPop() async {
    if (_hasUnsavedChanges) {
      final t = AppLocalizations.of(context)!;
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unsaved Changes'),
          content: const Text(
              'You have unsaved changes. Do you want to discard them?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t.actionCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      return result ?? false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.projectName),
          actions: [
            if (_hasUnsavedChanges)
              IconButton(
                icon: const Icon(RemixIcon.save3Line),
                tooltip: t.actionSaveFile,
                onPressed: _saveAll,
              ),
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'save_all':
                    _saveAll();
                    break;
                  case 'build':
                    _triggerBuild();
                    break;
                  case 'up':
                    _triggerUp();
                    break;
                  case 'down':
                    _triggerDown();
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'save_all',
                  child: ListTile(
                    leading: const Icon(RemixIcon.save3Line),
                    title: Text(t.msgSaveAll),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'build',
                  child: ListTile(
                    leading: const Icon(RemixIcon.toolsLine),
                    title: Text(t.actionBuildImage),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    enabled: !_isBuilding,
                  ),
                ),
                PopupMenuItem(
                  value: 'up',
                  child: ListTile(
                    leading: const Icon(RemixIcon.playCircleLine),
                    title: Text(t.actionComposeUp),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'down',
                  child: ListTile(
                    leading: const Icon(RemixIcon.stopCircleLine),
                    title: Text(t.actionComposeDown),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
        body: _isLoadingFiles
            ? const LoadingView(type: LoadingType.card)
            : _loadError != null
                ? ErrorView(
                    message: _loadError!,
                    onRetry: _loadAll,
                  )
                : Column(
                    children: [
                      // 状态栏
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        color: colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        child: Row(
                          children: [
                            _buildStatusChip(),
                            const Spacer(),
                            // 快速操作按钮
                            _ActionButton(
                              icon: RemixIcon.save3Line,
                              label: t.actionSaveFile,
                              onPressed: _saveAll,
                            ),
                            const SizedBox(width: 8),
                            _ActionButton(
                              icon: RemixIcon.toolsLine,
                              label: t.actionBuildImage,
                              onPressed: _isBuilding ? null : _triggerBuild,
                              isLoading: _isBuilding,
                            ),
                            const SizedBox(width: 8),
                            _ActionButton(
                              icon: RemixIcon.playCircleLine,
                              label: t.actionComposeUp,
                              onPressed: _triggerUp,
                            ),
                            const SizedBox(width: 8),
                            _ActionButton(
                              icon: RemixIcon.stopCircleLine,
                              label: t.actionComposeDown,
                              onPressed: _triggerDown,
                            ),
                          ],
                        ),
                      ),
                      // 文件标签栏
                      TabBar(
                        controller: _tabController,
                        tabs: [
                          Tab(text: t.labelFileDockerfile),
                          Tab(text: t.labelFileCompose),
                        ],
                      ),
                      // 编辑器
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            CodeEditor(
                              content: _dockerfileContent,
                              onChanged: (value) {
                                setState(() {
                                  _dockerfileContent = value;
                                });
                              },
                              language: 'dockerfile',
                            ),
                            CodeEditor(
                              content: _composeContent,
                              onChanged: (value) {
                                setState(() {
                                  _composeContent = value;
                                });
                              },
                              language: 'yaml',
                            ),
                          ],
                        ),
                      ),
                      // 构建日志区域
                      if (_showBuildLog && _buildLogController != null)
                        SizedBox(
                          child: BuildLogView(
                            logStream: _buildLogController!.stream,
                            onBuildComplete: () {
                              setState(() {
                                _isBuilding = false;
                              });
                              _loadProjectInfo();
                            },
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildStatusChip() {
    Color statusColor;
    switch (_projectStatus) {
      case 'running':
        statusColor = Colors.green;
        break;
      case 'building':
        statusColor = Colors.orange;
        break;
      case 'failed':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _projectStatus,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// 小型操作按钮
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 36,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: isLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          side: BorderSide(color: colorScheme.outline),
        ),
      ),
    );
  }
}
