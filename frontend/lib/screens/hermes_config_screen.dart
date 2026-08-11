import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/services/auth_service.dart';
import 'package:mobile_portainer_flutter_module/utils/notify_utils.dart';
import 'package:mobile_portainer_flutter_module/widgets/error_view.dart';
import 'package:mobile_portainer_flutter_module/widgets/loading_view.dart';

/// Hermes 接入配置页 — 查看并设置其他设备上部署的 hermes 实例的接入配置。
///
/// 配置优先级：前端设置保存的配置 > 后端环境变量（HERMES_BASE_URL /
/// HERMES_API_KEY / HERMES_MODEL），保存后立即生效无需重启。
/// 本页展示接入状态（启用/来源/实例地址/模型/Key 状态），可编辑配置并
/// 通过「测试连接」验证实例可达性与密钥有效性。
class HermesConfigScreen extends StatefulWidget {
  const HermesConfigScreen({super.key});

  @override
  State<HermesConfigScreen> createState() => _HermesConfigScreenState();
}

class _HermesConfigScreenState extends State<HermesConfigScreen> {
  Map<String, dynamic>? _status;
  bool _isLoading = true;
  String? _loadError;

  // 编辑表单状态
  final _formKey = GlobalKey<FormState>();
  bool _isEditing = false;
  bool _isSaving = false;
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final status = await AuthService.getHermesStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _testConnection() async {
    final t = AppLocalizations.of(context)!;
    try {
      final status = await AuthService.getHermesStatus();
      if (!mounted) return;
      setState(() => _status = status);

      final test = status['test'] as Map<String, dynamic>? ?? {};
      final ok = test['ok'] == true;
      NotifyUtils.showNotify(
        context,
        ok ? t.hermesTestResultOk : '${t.hermesTestResultFail}：${test['message']}',
      );
    } catch (e) {
      if (!mounted) return;
      NotifyUtils.showNotify(context, '${t.hermesTestResultFail}：$e');
    }
  }

  /// 进入编辑模式：用当前生效配置回填表单（API Key 留空表示不修改）。
  void _startEdit() {
    _baseUrlController.text = _status?['base_url']?.toString() ?? '';
    _apiKeyController.text = '';
    _modelController.text = _status?['model']?.toString() ?? '';
    setState(() => _isEditing = true);
  }

  void _cancelEdit() {
    FocusScope.of(context).unfocus();
    setState(() {
      _isEditing = false;
      _isSaving = false;
    });
  }

  Future<void> _saveConfig() async {
    final t = AppLocalizations.of(context)!;
    if (_isSaving || !_formKey.currentState!.validate()) return;

    // 先取消所有输入框焦点，避免 Web 端焦点冲突
    FocusScope.of(context).unfocus();

    setState(() => _isSaving = true);
    try {
      await AuthService.saveHermesConfig(
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        model: _modelController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _isEditing = false;
      });
      NotifyUtils.showNotify(context, t.hermesConfigSaved);
      await _loadStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      NotifyUtils.showNotify(context, '${t.hermesTestResultFail}：$e');
    }
  }

  /// base_url 校验：允许空（= 禁用接入），非空必须是合法的 http(s) 地址。
  String? _validateBaseUrl(String? value) {
    final t = AppLocalizations.of(context)!;
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    final valid =
        (v.startsWith('http://') || v.startsWith('https://')) && !v.contains(' ');
    return valid ? null : t.hermesUrlInvalid;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(t.titleHermes)),
      body: _isLoading
          ? const LoadingView()
          : _loadError != null
              ? ErrorView(message: _loadError!, onRetry: _loadStatus, retryLabel: t.msgRetry)
              : RefreshIndicator(
                  onRefresh: _loadStatus,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      if (_isEditing) ...[
                        _buildEditCard(t, colorScheme, textTheme),
                        const SizedBox(height: 16),
                      ],
                      _buildStatusCard(t, colorScheme, textTheme),
                      const SizedBox(height: 16),
                      _buildInfoCard(t, colorScheme, textTheme),
                      const SizedBox(height: 16),
                      _buildEnvNote(t, colorScheme, textTheme),
                    ],
                  ),
                ),
    );
  }

  /// 编辑表单卡片：实例地址 / API Key / 默认模型 + 保存 / 取消。
  Widget _buildEditCard(
    AppLocalizations t,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final keyConfigured = _status?['api_key_configured'] == true;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.hermesEditConfig, style: textTheme.titleMedium),
              const SizedBox(height: 12),
              TextFormField(
                controller: _baseUrlController,
                decoration: InputDecoration(
                  labelText: t.hermesLabelBaseUrl,
                  hintText: t.hintHermesBaseUrl,
                  border: const OutlineInputBorder(),
                ),
                validator: _validateBaseUrl,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _apiKeyController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: t.hermesLabelApiKey,
                  hintText: keyConfigured ? t.hintApiKeyKeep : t.hintApiKeyNew,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _modelController,
                decoration: InputDecoration(
                  labelText: t.hermesLabelModel,
                  hintText: t.hintHermesModel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _saveConfig,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(RemixIcon.saveLine),
                      label: Text(t.hermesSaveConfig),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _isSaving ? null : _cancelEdit,
                    child: Text(t.hermesCancelEdit),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部状态卡片：已启用 / 未配置 + 测试结果。
  Widget _buildStatusCard(
    AppLocalizations t,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final enabled = _status?['enabled'] == true;
    final test = _status?['test'] as Map<String, dynamic>? ?? {};
    final testOk = test['ok'] == true;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: enabled
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  child: Icon(
                    enabled ? RemixIcon.linkM : RemixIcon.linkUnlinkM,
                    color: enabled
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        enabled ? t.hermesStatusEnabled : t.hermesStatusDisabled,
                        style: textTheme.titleMedium,
                      ),
                      Text(
                        t.hermesSubtitle,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: t.hermesRefresh,
                  icon: const Icon(RemixIcon.refreshLine),
                  onPressed: _loadStatus,
                ),
              ],
            ),
            if (!enabled) ...[
              const SizedBox(height: 12),
              Text(
                t.hermesStatusDisabledHint,
                style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
              ),
            ],
            const Divider(height: 24),
            Row(
              children: [
                Icon(
                  testOk ? RemixIcon.checkboxCircleFill : RemixIcon.errorWarningFill,
                  size: 18,
                  color: testOk ? colorScheme.primary : colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${t.hermesLabelTestResult}：${test['message'] ?? '-'}',
                    style: textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _isEditing ? null : _startEdit,
                    icon: const Icon(RemixIcon.editLine),
                    label: Text(t.hermesEditConfig),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _testConnection,
                    icon: const Icon(RemixIcon.flaskLine),
                    label: Text(t.hermesTestConnection),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 配置信息卡片：来源 / 实例地址 / 默认模型 / API Key 状态。
  Widget _buildInfoCard(
    AppLocalizations t,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final baseUrl = _status?['base_url']?.toString() ?? '';
    final model = _status?['model']?.toString() ?? '';
    final keyConfigured = _status?['api_key_configured'] == true;
    final sourceDatabase = _status?['source'] == 'database';

    Widget row(String label, String value, {Color? valueColor}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(label, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
            ),
            Expanded(
              child: Text(
                value,
                style: textTheme.bodyMedium?.copyWith(color: valueColor),
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row(
              t.hermesLabelSource,
              sourceDatabase ? t.hermesSourceDatabase : t.hermesSourceEnv,
              valueColor: sourceDatabase ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            row(t.hermesLabelBaseUrl, baseUrl.isEmpty ? '-' : baseUrl),
            row(t.hermesLabelModel, model.isEmpty ? '-' : model),
            row(
              t.hermesLabelApiKey,
              keyConfigured ? t.hermesApiKeyConfigured : t.hermesApiKeyNotConfigured,
              valueColor: keyConfigured ? colorScheme.primary : colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }

  /// 配置优先级说明。
  Widget _buildEnvNote(
    AppLocalizations t,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(RemixIcon.informationLine, size: 16, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t.hermesEnvVarNote,
              style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
