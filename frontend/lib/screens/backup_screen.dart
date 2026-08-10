import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/models/backup.dart';
import 'package:mobile_portainer_flutter_module/services/backup_service.dart';
import 'package:mobile_portainer_flutter_module/services/platform/preferences_service.dart';
import 'package:mobile_portainer_flutter_module/utils/file_helper.dart';
import 'package:mobile_portainer_flutter_module/utils/notify_utils.dart';
import 'package:mobile_portainer_flutter_module/utils/platform_detector.dart';
import 'package:mobile_portainer_flutter_module/widgets/empty_view.dart';
import 'package:mobile_portainer_flutter_module/widgets/error_view.dart';

/// 备份与恢复页面：定时备份配置、手动创建备份、备份列表（恢复/下载/删除）。
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  /// 输入 RESTORE 才能执行恢复操作（危险操作双保险）。
  static const String restoreConfirmToken = 'RESTORE';

  String _apiUrl = '';
  String _apiKey = '';
  bool _ignoreSsl = false;
  BackupService? _service;

  List<BackupItem> _backups = [];
  BackupSchedule _schedule = const BackupSchedule(
    enabled: false,
    cron: '',
    keepDays: 30,
  );

  bool _isLoading = true;
  String? _error;
  bool _isCreating = false;
  bool _isSavingSchedule = false;

  /// 简单/高级模式：简单模式用每天执行时间生成 cron，高级模式直接编辑表达式。
  bool _advancedMode = false;

  /// 简单模式下的每天执行时间（HH:mm），默认 02:00。
  String _dailyTime = '02:00';

  final TextEditingController _cronController = TextEditingController();
  final TextEditingController _keepDaysController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettingsAndFetch();
  }

  @override
  void dispose() {
    _cronController.dispose();
    _keepDaysController.dispose();
    super.dispose();
  }

  Future<void> _loadSettingsAndFetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final prefs = await PreferencesService.getInstance();
    final url = prefs.getString('docker_api_url') ?? 'http://10.0.2.2:2375';
    final apiKey = prefs.getString('docker_api_key') ?? '';
    final ignoreSsl = prefs.getString('docker_ignore_ssl') == 'true';
    _apiUrl = url;
    _apiKey = apiKey;
    _ignoreSsl = ignoreSsl;
    _service = BackupService(
      baseUrl: _apiUrl,
      apiKey: _apiKey,
      ignoreSsl: _ignoreSsl,
    );
    await _fetchAll();
  }

  Future<void> _fetchAll() async {
    final service = _service;
    if (service == null) return;
    try {
      final results = await Future.wait([
        service.listBackups(),
        service.getSchedule(),
      ]);
      if (!mounted) return;
      setState(() {
        _backups = results[0] as List<BackupItem>;
        final schedule = results[1] as BackupSchedule;
        _schedule = schedule;
        _keepDaysController.text = schedule.keepDays.toString();
        _dailyTime = _timeFromCron(schedule.cron);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 从 cron 表达式解析每天执行时间（HH:mm）；非"每天"形式的表达式回退默认值。
  String _timeFromCron(String cron) {
    final fields = cron.trim().split(RegExp(r'\s+'));
    if (fields.length == 5) {
      final minute = int.tryParse(fields[0]);
      final hour = int.tryParse(fields[1]);
      final day = fields[2];
      final month = fields[3];
      final weekday = fields[4];
      if (minute != null &&
          hour != null &&
          day == '*' &&
          month == '*' &&
          weekday == '*') {
        return '${_pad2(hour)}:${_pad2(minute)}';
      }
    }
    return '02:00';
  }

  /// 简单模式 cron：每天 HH:MM。
  String get _simpleCron {
    final parts = _dailyTime.split(':');
    final minute = int.tryParse(parts[1]) ?? 0;
    final hour = int.tryParse(parts[0]) ?? 2;
    return '$minute $hour * * *';
  }

  String _pad2(int v) => v.toString().padLeft(2, '0');

  Future<void> _refresh() async {
    await _fetchAll();
  }

  Future<void> _createBackup() async {
    final t = AppLocalizations.of(context)!;
    final service = _service;
    if (service == null || _isCreating) return;
    setState(() {
      _isCreating = true;
    });
    try {
      await service.createBackup();
      if (!mounted) return;
      NotifyUtils.showNotify(context, t.msgBackupCreated);
      await _fetchAll();
    } catch (e) {
      if (!mounted) return;
      NotifyUtils.showNotify(context, t.msgBackupCreateFailed);
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  Future<void> _saveSchedule() async {
    final t = AppLocalizations.of(context)!;
    final service = _service;
    if (service == null || _isSavingSchedule) return;
    final cron = _advancedMode
        ? _cronController.text.trim()
        : _simpleCron;
    final keepDays = int.tryParse(_keepDaysController.text.trim()) ?? 0;
    setState(() {
      _isSavingSchedule = true;
    });
    try {
      final updated = await service.saveSchedule(
        enabled: _schedule.enabled,
        cron: cron,
        keepDays: keepDays,
      );
      if (!mounted) return;
      setState(() {
        _schedule = updated;
        _keepDaysController.text = updated.keepDays.toString();
        _dailyTime = _timeFromCron(updated.cron);
      });
      NotifyUtils.showNotify(context, t.msgScheduleSaved);
    } catch (e) {
      if (!mounted) return;
      NotifyUtils.showNotify(context, t.msgScheduleSaveFailed);
    } finally {
      if (mounted) {
        setState(() {
          _isSavingSchedule = false;
        });
      }
    }
  }

  Future<void> _pickDailyTime() async {
    final parts = _dailyTime.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 2,
      minute: int.tryParse(parts[1]) ?? 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;
    setState(() {
      _dailyTime = '${_pad2(picked.hour)}:${_pad2(picked.minute)}';
    });
  }

  void _showRestoreDialog(BackupItem item) {
    final t = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.labelRestoreBackup),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.msgRestoreWarning),
            const SizedBox(height: 8),
            Text(
              item.filename,
              style: Theme.of(dialogContext)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: t.hintRestoreConfirm,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t.actionCancel),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => FilledButton(
              onPressed: value.text == restoreConfirmToken
                  ? () {
                      Navigator.pop(dialogContext);
                      _doRestore(item);
                    }
                  : null,
              child: Text(t.labelRestore),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _doRestore(BackupItem item) async {
    final t = AppLocalizations.of(context)!;
    final service = _service;
    if (service == null) return;
    try {
      await service.restoreBackup(item.filename);
      if (!mounted) return;
      NotifyUtils.showNotify(context, t.msgRestoreStarted);
    } catch (e) {
      if (!mounted) return;
      NotifyUtils.showNotify(context, t.msgRestoreFailed);
    }
  }

  void _showDeleteDialog(BackupItem item) {
    final t = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.msgDeleteBackupConfirm),
        content: Text(
          item.filename,
          style: Theme.of(dialogContext)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t.actionCancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _doDelete(item);
            },
            child: Text(t.actionDelete),
          ),
        ],
      ),
    );
  }

  Future<void> _doDelete(BackupItem item) async {
    final t = AppLocalizations.of(context)!;
    final service = _service;
    if (service == null) return;
    try {
      await service.deleteBackup(item.filename);
      if (!mounted) return;
      NotifyUtils.showNotify(context, t.msgBackupDeleted);
      await _fetchAll();
    } catch (e) {
      if (!mounted) return;
      NotifyUtils.showNotify(context, t.msgBackupDeleteFailed);
    }
  }

  Future<void> _downloadBackup(BackupItem item) async {
    final t = AppLocalizations.of(context)!;
    final service = _service;
    if (service == null) return;
    try {
      final bytes = await service.downloadBackup(item.filename);
      if (PlatformDetector.isWeb) {
        await FileHelper.triggerDownload(item.filename, bytes);
      } else {
        final dirPath = await FileHelper.downloadDirPath();
        if (dirPath == null) {
          throw Exception('Could not find download directory');
        }
        await FileHelper.ensureDir(dirPath);
        await FileHelper.writeBytes('$dirPath/${item.filename}', bytes);
      }
      if (!mounted) return;
      NotifyUtils.showNotify(context, t.msgBackupDownloaded);
    } catch (e) {
      if (!mounted) return;
      NotifyUtils.showNotify(context, t.msgDownloadFailed);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// YYYYMMDDHHMMSS → YYYY-MM-DD HH:MM。
  String _formatDateTime(String raw) {
    if (raw.length < 12) return raw;
    return '${raw.substring(0, 4)}-${raw.substring(4, 6)}-'
        '${raw.substring(6, 8)} ${raw.substring(8, 10)}:${raw.substring(10, 12)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(t.titleBackupRestore)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorView(message: _error!, onRetry: _loadSettingsAndFetch)
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      _buildScheduleCard(t),
                      const SizedBox(height: 16),
                      _buildCreateButton(t),
                      const SizedBox(height: 24),
                      _buildBackupList(t),
                    ],
                  ),
                ),
    );
  }

  Widget _buildScheduleCard(AppLocalizations t) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: Text(t.labelEnableSchedule),
              subtitle: Text(t.labelSchedule),
              value: _schedule.enabled,
              onChanged: (v) => setState(() {
                _schedule = BackupSchedule(
                  enabled: v,
                  cron: _schedule.cron,
                  keepDays: _schedule.keepDays,
                  nextFire: _schedule.nextFire,
                );
              }),
            ),
            if (_schedule.enabled) ...[
              if (!_advancedMode)
                ListTile(
                  leading: const Icon(RemixIcon.timeLine),
                  title: Text(t.labelDailyTime),
                  trailing: Text(
                    _dailyTime,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  onTap: _pickDailyTime,
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: TextField(
                    key: const Key('cron_field'),
                    controller: _cronController,
                    decoration: InputDecoration(
                      labelText: t.labelCronExpression,
                      hintText: t.hintCronExpression,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _advancedMode = !_advancedMode;
                        if (_advancedMode) {
                          _cronController.text = _schedule.cron.isNotEmpty
                              ? _schedule.cron
                              : _simpleCron;
                        }
                      });
                    },
                    child: Text(
                      _advancedMode ? t.labelSimpleMode : t.labelAdvancedMode,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: TextField(
                  key: const Key('keep_days_field'),
                  controller: _keepDaysController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: t.labelKeepDays,
                    suffixText: t.labelDays,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              if (_schedule.nextFire != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    '${t.labelNextBackup}: ${_formatDateTime(_schedule.nextFire!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSavingSchedule ? null : _saveSchedule,
                    child: _isSavingSchedule
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(t.buttonSave),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCreateButton(AppLocalizations t) {
    return FilledButton.icon(
      onPressed: _isCreating ? null : _createBackup,
      icon: _isCreating
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(RemixIcon.refreshLine),
      label: Text(t.buttonCreateBackup),
    );
  }

  Widget _buildBackupList(AppLocalizations t) {
    if (_backups.isEmpty) {
      return EmptyView(
        icon: RemixIcon.archiveLine,
        message: t.msgNoBackups,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.labelBackupList,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ..._backups.map(_buildBackupItem),
      ],
    );
  }

  Widget _buildBackupItem(BackupItem item) {
    final t = AppLocalizations.of(context)!;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          item.filename,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_formatSize(item.size)} | ${_formatDateTime(item.createdAt)}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: t.labelRestore,
              icon: const Icon(RemixIcon.historyLine),
              onPressed: () => _showRestoreDialog(item),
            ),
            IconButton(
              tooltip: t.labelDownload,
              icon: const Icon(RemixIcon.downloadLine),
              onPressed: () => _downloadBackup(item),
            ),
            IconButton(
              tooltip: t.actionDelete,
              icon: const Icon(RemixIcon.deleteBinLine),
              onPressed: () => _showDeleteDialog(item),
            ),
          ],
        ),
      ),
    );
  }
}
