import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/services/platform/preferences_service.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import '../widgets/loading_view.dart';

class EnvVarsScreen extends StatefulWidget {
  const EnvVarsScreen({super.key});

  @override
  State<EnvVarsScreen> createState() => _EnvVarsScreenState();
}

class _EnvVarsScreenState extends State<EnvVarsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, String>> _globalVars = [];
  List<Map<String, dynamic>> _groups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await PreferencesService.getInstance();
    
    // Load global vars
    final globalJson = prefs.getString('env_vars_global');
    if (globalJson != null) {
      try {
        final List<dynamic> list = json.decode(globalJson);
        _globalVars = list.map((e) => Map<String, String>.from(e)).toList();
      } catch (e) {
        debugPrint('Error loading global vars: $e');
      }
    }

    // Load groups
    final groupsJson = prefs.getString('env_vars_groups');
    if (groupsJson != null) {
      try {
        final List<dynamic> list = json.decode(groupsJson);
        _groups = list.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (e) {
        debugPrint('Error loading groups: $e');
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveGlobalVars() async {
    final prefs = await PreferencesService.getInstance();
    await prefs.setString('env_vars_global', json.encode(_globalVars));
  }

  Future<void> _saveGroups() async {
    final prefs = await PreferencesService.getInstance();
    await prefs.setString('env_vars_groups', json.encode(_groups));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Column(
      children: [
        Material(
          color: Theme.of(context).cardColor,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: Theme.of(context).primaryColor,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
            tabs: [
              Tab(text: t.tabGlobal),
              Tab(text: t.tabGroups),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const LoadingView(type: LoadingType.list)
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildGlobalTab(t),
                    _buildGroupsTab(t),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildGlobalTab(AppLocalizations t) {
    return Scaffold(
      body: _globalVars.isEmpty
          ? Center(child: Text(t.msgNoLogs))
          : ListView.builder(
              itemCount: _globalVars.length,
              itemBuilder: (context, index) {
                final item = _globalVars[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    title: Text(item['key'] ?? ''),
                    subtitle: Text(item['value'] ?? ''),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(RemixIcon.editLine, color: Theme.of(context).colorScheme.primary),
                          onPressed: () => _showAddEditVarDialog(context, t, index: index),
                        ),
                        IconButton(
                          icon: Icon(RemixIcon.deleteBinLine, color: Theme.of(context).colorScheme.error),
                          onPressed: () => _deleteGlobalVar(index, t),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_add_env_var',
        onPressed: () => _showAddEditVarDialog(context, t),
        child: const Icon(RemixIcon.addLine),
      ),
    );
  }

  Widget _buildGroupsTab(AppLocalizations t) {
    return Scaffold(
      body: _groups.isEmpty
          ? Center(child: Text(t.msgNoLogs))
          : ListView.builder(
              itemCount: _groups.length,
              itemBuilder: (context, index) {
                final group = _groups[index];
                final vars = (group['vars'] as List?) ?? [];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ExpansionTile(
                    title: Text(group['name'] ?? ''),
                    subtitle: Text('${vars.length} variables'),
                    children: [
                      ...vars.map((v) => ListTile(
                        title: Text(v['key']),
                        subtitle: Text(v['value']),
                        dense: true,
                      )),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            child: Text(t.actionEdit),
                            onPressed: () => _showAddEditGroupDialog(context, t, index: index),
                          ),
                          TextButton(
                            child: Text(t.actionDelete, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                            onPressed: () => _deleteGroup(index, t),
                          ),
                        ],
                      )
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_add_env_group',
        onPressed: () => _showAddEditGroupDialog(context, t),
        child: const Icon(RemixIcon.addLine),
      ),
    );
  }

  void _deleteGlobalVar(int index, AppLocalizations t) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.titleConfirmDelete),
        content: Text(t.msgConfirmDelete),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.actionCancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() {
                _globalVars.removeAt(index);
              });
              await _saveGlobalVars();
            },
            child: Text(t.actionDelete, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  void _deleteGroup(int index, AppLocalizations t) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.titleConfirmDelete),
        content: Text(t.msgConfirmDelete),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.actionCancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() {
                _groups.removeAt(index);
              });
              await _saveGroups();
            },
            child: Text(t.actionDelete, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddEditVarDialog(BuildContext context, AppLocalizations t, {int? index}) async {
    final keyController = TextEditingController(
      text: index != null ? _globalVars[index]['key'] : ''
    );
    final valueController = TextEditingController(
      text: index != null ? _globalVars[index]['value'] : ''
    );

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(index != null ? t.actionEdit : t.msgVarAdded.replaceAll('ed', '')), // "Variable Add" hack or just Title
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyController,
              decoration: InputDecoration(labelText: t.labelKey),
            ),
            TextField(
              controller: valueController,
              decoration: InputDecoration(labelText: t.labelValue),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.actionCancel),
          ),
          ElevatedButton(
            onPressed: () async {
              if (keyController.text.isEmpty) return;
              Navigator.pop(ctx);
              setState(() {
                final newVar = {
                  'key': keyController.text,
                  'value': valueController.text,
                };
                if (index != null) {
                  _globalVars[index] = newVar;
                } else {
                  _globalVars.add(newVar);
                }
              });
              await _saveGlobalVars();
            },
            child: Text(t.buttonSave),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddEditGroupDialog(BuildContext context, AppLocalizations t, {int? index}) async {
    final nameController = TextEditingController(
      text: index != null ? _groups[index]['name'] : ''
    );
    // Deep copy current vars or empty
    List<Map<String, String>> tempVars = [];
    if (index != null) {
      final currentVars = _groups[index]['vars'] as List;
      tempVars = currentVars.map((e) => Map<String, String>.from(e)).toList();
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text(index != null ? t.actionEdit : t.msgGroupAdded.replaceAll('ed', '')),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(labelText: t.labelGroupName),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(t.titleEnvVars, style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(RemixIcon.addCircleLine),
                        onPressed: () async {
                          final newVar = await _showInlineVarDialog(context, t);
                          if (newVar != null) {
                            setStateDialog(() {
                              tempVars.add(newVar);
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: tempVars.length,
                      itemBuilder: (context, i) {
                        return ListTile(
                          title: Text(tempVars[i]['key']!),
                          subtitle: Text(tempVars[i]['value']!),
                          trailing: IconButton(
                            icon: Icon(RemixIcon.indeterminateCircleLine, color: Theme.of(context).colorScheme.error),
                            onPressed: () {
                              setStateDialog(() {
                                tempVars.removeAt(i);
                              });
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(t.actionCancel),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.isEmpty) return;
                  Navigator.pop(ctx);
                  setState(() {
                    final newGroup = {
                      'name': nameController.text,
                      'vars': tempVars,
                    };
                    if (index != null) {
                      _groups[index] = newGroup;
                    } else {
                      _groups.add(newGroup);
                    }
                  });
                  await _saveGroups();
                },
                child: Text(t.buttonSave),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<Map<String, String>?> _showInlineVarDialog(BuildContext context, AppLocalizations t) async {
    final keyController = TextEditingController();
    final valueController = TextEditingController();
    return showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.msgVarAdded.replaceAll('ed', '')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyController,
              decoration: InputDecoration(labelText: t.labelKey),
            ),
            TextField(
              controller: valueController,
              decoration: InputDecoration(labelText: t.labelValue),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.actionCancel),
          ),
          ElevatedButton(
            onPressed: () {
              if (keyController.text.isNotEmpty) {
                Navigator.pop(ctx, {
                  'key': keyController.text,
                  'value': valueController.text,
                });
              }
            },
            child: Text(t.buttonSave),
          ),
        ],
      ),
    );
  }
}
