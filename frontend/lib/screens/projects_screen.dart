import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/services/platform/preferences_service.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/utils/api_error_handler.dart';
import '../services/docker_service.dart';
import '../models/project.dart';
import '../widgets/app_search_bar.dart';
import '../widgets/error_view.dart';
import '../widgets/empty_view.dart';
import '../widgets/loading_view.dart';
import 'project_detail_screen.dart';

class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key});

  @override
  State<ProjectListScreen> createState() => ProjectListScreenState();
}

class ProjectListScreenState extends State<ProjectListScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Project> _allProjects = [];
  List<Project> _filteredProjects = [];
  bool _isLoading = false;
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
    _fetchProjects();
  }

  void refresh() {
    _loadSettingsAndFetch();
  }

  bool get isLoading => _isLoading;
  Future<void> manualRefresh() => _fetchProjects();

  Future<void> _fetchProjects() async {
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
      final projects = await service.getProjects();
      if (!mounted) return;
      setState(() {
        _allProjects = projects;
        _filterProjects();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        ApiErrorHandler.show(context, e);
        _error = e.toString();
        _isLoading = false;
        _allProjects = [];
        _filteredProjects = [];
      });
    }
  }

  void _filterProjects() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredProjects = _allProjects.where((project) {
        return query.isEmpty ||
            project.name.toLowerCase().contains(query) ||
            project.description.toLowerCase().contains(query);
      }).toList();
    });
  }

  Future<void> _createProject() async {
    final t = AppLocalizations.of(context)!;
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.actionCreateProject),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: t.labelProjectName,
                  hintText: t.hintProjectName,
                ),
                autofocus: true,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return t.hintProjectName;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: descController,
                decoration: InputDecoration(
                  labelText: t.labelProjectDescription,
                  hintText: t.hintProjectDescription,
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.actionCancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: Text(t.actionCreateProject),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final service = DockerService(
        baseUrl: _currentApiUrl,
        apiKey: _currentApiKey,
        ignoreSsl: _currentIgnoreSsl,
      );
      try {
        await service.createProject(
          nameController.text.trim(),
          descController.text.trim(),
        );
        if (!mounted) return;
        ApiErrorHandler.show(context, t.msgProjectCreated);
        _fetchProjects();
      } catch (e) {
        if (!mounted) return;
        ApiErrorHandler.handle(context, e);
      }
    }
  }

  Future<void> _deleteProject(Project project) async {
    final t = AppLocalizations.of(context)!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.titleConfirmDelete),
        content: Text(t.msgConfirmDeleteProject),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(t.actionDelete),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final service = DockerService(
        baseUrl: _currentApiUrl,
        apiKey: _currentApiKey,
        ignoreSsl: _currentIgnoreSsl,
      );
      try {
        await service.deleteProject(project.id);
        if (!mounted) return;
        ApiErrorHandler.show(context, t.msgProjectDeleted);
        _fetchProjects();
      } catch (e) {
        if (!mounted) return;
        ApiErrorHandler.handle(context, e);
      }
    }
  }

  void _openProject(Project project) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProjectDetailScreen(
          projectId: project.id,
          projectName: project.name,
          apiUrl: _currentApiUrl,
          apiKey: _currentApiKey,
          ignoreSsl: _currentIgnoreSsl,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Color _statusColor(String status, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (status) {
      case 'running':
        return isDark ? const Color(0xFF52CC6D) : const Color(0xFF00B42A);
      case 'building':
        return isDark ? const Color(0xFFFF9933) : const Color(0xFFFF7D00);
      case 'failed':
        return isDark ? const Color(0xFFF76560) : const Color(0xFFF53F3F);
      default:
        return isDark ? const Color(0xFF86909C) : const Color(0xFF86909C);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    if (_error != null) {
      return ErrorView(
        message: _error!,
        onRetry: _loadSettingsAndFetch,
        retryLabel: t.msgRetry,
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            AppSearchBar(
              controller: _searchController,
              hintText: t.hintSearchProjects,
              onChanged: (_) => _filterProjects(),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchProjects,
                child: _isLoading
                    ? const LoadingView(type: LoadingType.list)
                    : _filteredProjects.isEmpty
                        ? EmptyView(
                            icon: RemixIcon.folderLine,
                            message: t.msgNoProjects,
                          )
                        : ListView.builder(
                            itemCount: _filteredProjects.length,
                            padding: const EdgeInsets.only(bottom: 80),
                            itemBuilder: (context, index) {
                              final project = _filteredProjects[index];
                              return _buildProjectCard(project, t, context);
                            },
                          ),
              ),
            ),
          ],
        ),
        // FAB 创建项目
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'fab_create_project',
            onPressed: _createProject,
            child: const Icon(RemixIcon.addLine),
          ),
        ),
      ],
    );
  }

  Widget _buildProjectCard(
      Project project, AppLocalizations t, BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openProject(project),
        onLongPress: () => _deleteProject(project),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      project.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(project.status, context)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _statusColor(project.status, context),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          project.status,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _statusColor(project.status, context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (project.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  project.description,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              Text(
                _formatDate(project.updatedAt),
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
