import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/services/auth_service.dart';
import 'package:mobile_portainer_flutter_module/utils/notify_utils.dart';
import 'package:mobile_portainer_flutter_module/widgets/error_view.dart';
import 'package:mobile_portainer_flutter_module/widgets/loading_view.dart';

/// Hermes 接入配置页 — 查看其他设备上部署的 hermes 实例的接入状态。
///
/// 配置来自后端环境变量（HERMES_BASE_URL / HERMES_API_KEY / HERMES_MODEL），
/// 本页只读展示状态，并提供「测试连接」验证实例可达性与密钥有效性。
class HermesConfigScreen extends StatefulWidget {
  const HermesConfigScreen({super.key});

  @override
  State<HermesConfigScreen> createState() => _HermesConfigScreenState();
}

class _HermesConfigScreenState extends State<HermesConfigScreen> {
  Map<String, dynamic>? _status;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadStatus();
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
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _testConnection,
                icon: const Icon(RemixIcon.flaskLine),
                label: Text(t.hermesTestConnection),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 配置信息卡片：实例地址 / 默认模型 / API Key 状态。
  Widget _buildInfoCard(
    AppLocalizations t,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final baseUrl = _status?['base_url']?.toString() ?? '';
    final model = _status?['model']?.toString() ?? '';
    final keyConfigured = _status?['api_key_configured'] == true;

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

  /// 环境变量说明。
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
