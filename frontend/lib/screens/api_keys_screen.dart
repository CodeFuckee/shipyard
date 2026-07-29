import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:flutter/services.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../utils/notify_utils.dart';
import 'package:mobile_portainer_flutter_module/utils/api_error_handler.dart';
import '../widgets/loading_view.dart';

class ApiKeysScreen extends StatefulWidget {
  const ApiKeysScreen({super.key});

  @override
  State<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends State<ApiKeysScreen> {
  List<Map<String, dynamic>> _keys = [];
  bool _isLoading = true;
  String? _error;
  final Set<int> _visibleKeys = {};

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final keys = await AuthService.getApiKeys();
      if (!mounted) return;
      setState(() {
        _keys = keys;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        ApiErrorHandler.show(context, e);
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _createKey() async {
    final t = AppLocalizations.of(context)!;
    final nameController = TextEditingController();
    final keyController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.actionCreateKey),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: t.labelApiKeyName,
                hintText: t.hintApiKeyName,
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: keyController,
              decoration: InputDecoration(
                labelText: t.labelApiKeyValue,
                hintText: t.hintApiKeyValue,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.actionCreateKey),
          ),
        ],
      ),
    );

    if (result != true || !mounted) return;

    final name = nameController.text.trim();
    if (name.isEmpty) return;

    final keyValue = keyController.text.trim();

    try {
      final newKey = await AuthService.createApiKey(
        name: name,
        key: keyValue.isNotEmpty ? keyValue : null,
      );
      if (!mounted) return;
      setState(() {
        _keys.insert(0, newKey);
      });
      NotifyUtils.showNotify(context, t.msgApiKeyCreated);
    } catch (e) {
      if (!mounted) return;
      NotifyUtils.showNotify(context, e.toString());
    }
  }

  Future<void> _deleteKey(Map<String, dynamic> key) async {
    final t = AppLocalizations.of(context)!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.actionDelete),
        content: Text(t.msgConfirmDeleteApiKey),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.actionDelete),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final keyId = key['id']?.toString() ?? key['key']?.toString() ?? '';
    if (keyId.isEmpty) return;

    try {
      await AuthService.deleteApiKey(keyId);
      if (!mounted) return;
      setState(() {
        _keys.removeWhere((k) {
          final id = k['id']?.toString() ?? k['key']?.toString() ?? '';
          return id == keyId;
        });
      });
      NotifyUtils.showNotify(context, t.msgApiKeyDeleted);
    } catch (e) {
      if (!mounted) return;
      NotifyUtils.showNotify(context, e.toString());
    }
  }

  void _copyKey(Map<String, dynamic> key) {
    final t = AppLocalizations.of(context)!;
    final keyValue = key['key']?.toString() ??
        key['apiKey']?.toString() ??
        key['token']?.toString() ??
        '';
    if (keyValue.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: keyValue));
      NotifyUtils.showNotify(context, t.msgApiKeyCopied);
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  String _maskApiKey(String key) {
    if (key.length <= 8) return '*' * key.length;
    return '${key.substring(0, 4)}****${key.substring(key.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.titleApiKeys),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_create_api_key',
        onPressed: _createKey,
        child: const Icon(RemixIcon.addLine),
      ),
      body: _buildBody(t),
    );
  }

  Widget _buildBody(AppLocalizations t) {
    if (_isLoading) {
      return const Center(child: LoadingView(type: LoadingType.list));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(RemixIcon.errorWarningLine, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(_error!, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadKeys,
              child: Text(t.msgRetry),
            ),
          ],
        ),
      );
    }

    if (_keys.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(RemixIcon.key2Line, size: 48, color: Theme.of(context).hintColor),
            const SizedBox(height: 16),
            Text(t.msgNoApiKeys, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadKeys,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _keys.length,
        itemBuilder: (context, index) {
          final key = _keys[index];
          return _buildKeyCard(key, t);
        },
      ),
    );
  }

  Widget _buildKeyCard(Map<String, dynamic> key, AppLocalizations t) {
    final keyValue = key['key']?.toString() ??
        key['apiKey']?.toString() ??
        key['token']?.toString() ??
        '';
    final name = key['name']?.toString() ?? key['id']?.toString() ?? 'Key';
    final createdAt = _formatDate(key['created_at']?.toString());
    final expiresAt = key['expires_at']?.toString();
    final keyHash = '$name-$createdAt-${keyValue.length}'.hashCode;
    final isVisible = _visibleKeys.contains(keyHash);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(isVisible ? RemixIcon.eyeOffLine : RemixIcon.eyeLine, size: 20),
                  onPressed: () {
                    setState(() {
                      if (isVisible) {
                        _visibleKeys.remove(keyHash);
                      } else {
                        _visibleKeys.add(keyHash);
                      }
                    });
                  },
                  tooltip: isVisible ? t.actionHide : t.actionShow,
                ),
                IconButton(
                  icon: const Icon(RemixIcon.fileCopyLine, size: 20),
                  onPressed: () => _copyKey(key),
                  tooltip: t.actionCopy,
                ),
                IconButton(
                  icon: Icon(RemixIcon.deleteBinLine, size: 20, color: Theme.of(context).colorScheme.error),
                  onPressed: () => _deleteKey(key),
                  tooltip: t.actionDelete,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(RemixIcon.key2Line, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isVisible ? keyValue : _maskApiKey(keyValue),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (createdAt.isNotEmpty || expiresAt != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (createdAt.isNotEmpty) ...[
                    Icon(RemixIcon.calendarLine, size: 14, color: Theme.of(context).hintColor),
                    const SizedBox(width: 4),
                    Text(
                      '${t.labelCreatedAt}: $createdAt',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                  if (createdAt.isNotEmpty && expiresAt != null) const Spacer(),
                  if (expiresAt != null) ...[
                    Icon(RemixIcon.timerLine, size: 14, color: Theme.of(context).hintColor),
                    const SizedBox(width: 4),
                    Text(
                      '${t.labelExpiresAt}: ${_formatDate(expiresAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
