import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/services/platform/preferences_service.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'loading_view.dart';

class EnvVarsSelector extends StatefulWidget {
  const EnvVarsSelector({super.key});

  @override
  State<EnvVarsSelector> createState() => _EnvVarsSelectorState();
}

class _EnvVarsSelectorState extends State<EnvVarsSelector> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, String>> _globalVars = [];
  List<Map<String, dynamic>> _groups = [];
  bool _isLoading = true;
  
  // Selection state
  final Set<int> _selectedGlobalIndices = {};
  final Set<int> _selectedGroupIndices = {}; // Groups are selected as a whole
  
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    int totalVars = _selectedGlobalIndices.length;
    for (var i in _selectedGroupIndices) {
      final group = _groups[i];
      final vars = (group['vars'] as List?) ?? [];
      totalVars += vars.length;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t.titleSelectEnvVars),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: t.tabGlobal),
            Tab(text: t.tabGroups),
          ],
        ),
      ),
      body: _isLoading
          ? const LoadingView(type: LoadingType.list)
          : TabBarView(
              controller: _tabController,
              children: [
                _buildGlobalTab(t),
                _buildGroupsTab(t),
              ],
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(t.labelSelectedCount(totalVars)),
            ElevatedButton(
              onPressed: totalVars > 0 ? () {
                final List<Map<String, String>> result = [];
                
                // Add global vars
                for (var i in _selectedGlobalIndices) {
                  result.add(_globalVars[i]);
                }
                
                // Add group vars
                for (var i in _selectedGroupIndices) {
                  final group = _groups[i];
                  final vars = (group['vars'] as List?) ?? [];
                  for (var v in vars) {
                    result.add(Map<String, String>.from(v));
                  }
                }
                
                Navigator.pop(context, result);
              } : null,
              child: const Icon(RemixIcon.checkLine),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalTab(AppLocalizations t) {
    if (_globalVars.isEmpty) {
      return Center(child: Text(t.msgNoLogs));
    }
    return ListView.builder(
      itemCount: _globalVars.length,
      itemBuilder: (context, index) {
        final item = _globalVars[index];
        final isSelected = _selectedGlobalIndices.contains(index);
        return CheckboxListTile(
          title: Text(item['key'] ?? ''),
          subtitle: Text(item['value'] ?? ''),
          value: isSelected,
          onChanged: (val) {
            setState(() {
              if (val == true) {
                _selectedGlobalIndices.add(index);
              } else {
                _selectedGlobalIndices.remove(index);
              }
            });
          },
        );
      },
    );
  }

  Widget _buildGroupsTab(AppLocalizations t) {
    if (_groups.isEmpty) {
      return Center(child: Text(t.msgNoLogs));
    }
    return ListView.builder(
      itemCount: _groups.length,
      itemBuilder: (context, index) {
        final group = _groups[index];
        final vars = (group['vars'] as List?) ?? [];
        final isSelected = _selectedGroupIndices.contains(index);
        
        return CheckboxListTile(
          title: Text(group['name'] ?? ''),
          subtitle: Text('${vars.length} variables'),
          value: isSelected,
          onChanged: (val) {
            setState(() {
              if (val == true) {
                _selectedGroupIndices.add(index);
              } else {
                _selectedGroupIndices.remove(index);
              }
            });
          },
          secondary: IconButton(
            icon: const Icon(RemixIcon.informationLine),
            onPressed: () {
               // Show group content preview
               showDialog(
                 context: context,
                 builder: (ctx) => AlertDialog(
                   title: Text(group['name']),
                   content: SingleChildScrollView(
                     child: Column(
                       mainAxisSize: MainAxisSize.min,
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: vars.map<Widget>((v) => Text('${v['key']}=${v['value']}')).toList(),
                     ),
                   ),
                   actions: [
                     TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))
                   ],
                 ),
               );
            },
          ),
        );
      },
    );
  }
}
