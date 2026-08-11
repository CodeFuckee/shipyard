import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/services/auth_service.dart';
import 'package:mobile_portainer_flutter_module/utils/notify_utils.dart';
import 'package:mobile_portainer_flutter_module/widgets/action_sheet.dart';
import 'package:mobile_portainer_flutter_module/widgets/empty_view.dart';
import 'package:mobile_portainer_flutter_module/widgets/error_view.dart';
import 'package:mobile_portainer_flutter_module/widgets/loading_view.dart';

/// AI API 供应商配置页 — 纯配置存储，为后续 AI 功能做准备。
///
/// 支持：添加 / 编辑 / 删除供应商，测试连接（验证 Base URL 与 API Key），
/// 内置 deepseek / openai 预设（选择后自动填充 Base URL 与默认模型）。
class AiProvidersScreen extends StatefulWidget {
  const AiProvidersScreen({super.key});

  @override
  State<AiProvidersScreen> createState() => _AiProvidersScreenState();
}

class _AiProvidersScreenState extends State<AiProvidersScreen> {
  List<dynamic> _providers = [];
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final providers = await AuthService.getAiProviders();
      if (!mounted) return;
      setState(() {
        _providers = providers;
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

  String _providerTypeLabel(AppLocalizations t, String type) {
    switch (type) {
      case 'deepseek':
        return t.labelProviderTypeDeepseek;
      case 'openai':
        return t.labelProviderTypeOpenai;
      default:
        return t.labelProviderTypeCustom;
    }
  }

  /// 内置预设：选择类型后自动填充 Base URL 与默认模型。
  (String, String)? _presetFor(String type) {
    switch (type) {
      case 'deepseek':
        return ('https://api.deepseek.com', 'deepseek-chat');
      case 'openai':
        return ('https://api.openai.com/v1', 'gpt-4o-mini');
      default:
        return null;
    }
  }

  /// 卡片操作菜单：测试连接 / 编辑 / 删除。
  /// 手机端走底部操作菜单，其他端走居中对话框（PlatformDialogs 自动处理）。
  void _showActions(Map<String, dynamic> provider) {
    final t = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    ActionSheet.show(
      context: context,
      header: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              RemixIcon.openaiLine,
              size: 20,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                provider['name']?.toString() ?? '',
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      actions: [
        ActionItem(
          label: t.actionTestConnection,
          icon: RemixIcon.radarLine,
          color: colorScheme.primary,
          actionCode: 'test',
        ),
        ActionItem(
          label: t.actionEdit,
          icon: RemixIcon.editLine,
          color: colorScheme.onSurface,
          actionCode: 'edit',
        ),
        ActionItem(
          label: t.actionDelete,
          icon: RemixIcon.deleteBinLine,
          color: colorScheme.error,
          actionCode: 'delete',
        ),
      ],
      onAction: (code) {
        switch (code) {
          case 'test':
            _testConnection(provider);
          case 'edit':
            _showProviderForm(provider: provider);
          case 'delete':
            _confirmDelete(provider);
        }
      },
    );
  }

  /// 测试连接（后端请求 OpenAI 兼容 /models 端点验证 Key）。
  Future<void> _testConnection(Map<String, dynamic> provider) async {
    final t = AppLocalizations.of(context)!;
    final id = provider['id']?.toString() ?? '';
    if (id.isEmpty) return;

    NotifyUtils.showNotify(context, t.msgTestConnecting);
    try {
      final result = await AuthService.testAiProvider(id: id);
      if (!mounted) return;
      final ok = result['ok'] == true;
      final message = result['message']?.toString() ?? '';
      NotifyUtils.showNotify(context, ok ? t.msgConnectionSuccess : t.msgConnectionFailed(message));
    } catch (e) {
      if (!mounted) return;
      NotifyUtils.showNotify(context, t.msgConnectionFailed(e.toString()));
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> provider) async {
    final t = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.actionDelete),
        content: Text(t.msgProviderDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await AuthService.deleteAiProvider(id: provider['id'].toString());
      if (!mounted) return;
      NotifyUtils.showNotify(context, t.msgProviderDeleted);
      await _loadProviders();
    } catch (e) {
      if (!mounted) return;
      NotifyUtils.showNotify(context, '${t.msgProviderDeleted}: ${e.toString()}');
    }
  }

  /// 添加 / 编辑供应商表单对话框。
  void _showProviderForm({Map<String, dynamic>? provider}) {
    final t = AppLocalizations.of(context)!;
    final isEdit = provider != null;
    final formKey = GlobalKey<FormState>();

    final nameController = TextEditingController(
      text: isEdit ? (provider['name']?.toString() ?? '') : '',
    );
    String providerType =
        isEdit ? (provider['provider_type']?.toString() ?? 'custom') : 'deepseek';
    final baseUrlController = TextEditingController(
      text: isEdit ? (provider['base_url']?.toString() ?? '') : 'https://api.deepseek.com',
    );
    final apiKeyController = TextEditingController();
    final modelController = TextEditingController(
      text: isEdit ? (provider['default_model']?.toString() ?? '') : 'deepseek-chat',
    );
    var enabled = isEdit ? provider['enabled'] != false : true;
    // 获取模型列表的进行中状态（仅编辑模式可用，需已创建的供应商 id）
    var fetchingModels = false;

    /// 通过后端代理请求 {base_url}/models 获取模型列表，弹窗选择后回填默认模型。
    Future<void> fetchModels(BuildContext dialogContext, StateSetter setDialogState) async {
      final t = AppLocalizations.of(dialogContext)!;
      if (!isEdit) return; // 新增模式下供应商尚未创建，无法拉取
      setDialogState(() => fetchingModels = true);
      try {
        final result =
            await AuthService.getAiProviderModels(id: provider['id'].toString());
        if (!dialogContext.mounted) return;
        setDialogState(() => fetchingModels = false);
        // ok=false 时展示后端返回的人类可读失败原因
        if (result['ok'] != true) {
          NotifyUtils.showNotify(
            dialogContext,
            result['message']?.toString() ?? t.msgModelsFetchFailed('未知错误'),
          );
          return;
        }
        final models = (result['models'] as List?) ?? const [];
        if (models.isEmpty) {
          NotifyUtils.showNotify(dialogContext, t.msgNoModelsFound);
          return;
        }
        final selected = await showDialog<String>(
          context: dialogContext,
          builder: (ctx) => AlertDialog(
            title: Text(t.labelSelectModel),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: models.length,
                itemBuilder: (ctx, index) {
                  final item = Map<String, dynamic>.from(models[index]);
                  final id = item['id']?.toString() ?? '';
                  final name = item['name']?.toString() ?? '';
                  return ListTile(
                    title: Text(name.isNotEmpty ? name : id),
                    subtitle: name.isNotEmpty && id.isNotEmpty && name != id
                        ? Text(id, style: Theme.of(ctx).textTheme.bodySmall)
                        : null,
                    onTap: () => Navigator.pop(ctx, id),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(t.actionCancel),
              ),
            ],
          ),
        );
        if (selected != null && selected.isNotEmpty && dialogContext.mounted) {
          setDialogState(() => modelController.text = selected);
        }
      } catch (e) {
        if (!dialogContext.mounted) return;
        setDialogState(() => fetchingModels = false);
        NotifyUtils.showNotify(dialogContext, t.msgModelsFetchFailed(e.toString()));
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final colorScheme = Theme.of(dialogContext).colorScheme;

            Widget buildSaveButton() {
              return FilledButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;

                  final name = nameController.text.trim();
                  final baseUrl = baseUrlController.text.trim();
                  final apiKey = apiKeyController.text.trim();
                  final model = modelController.text.trim();

                  try {
                    setDialogState(() {});
                    if (isEdit) {
                      await AuthService.updateAiProvider(
                        id: provider['id'].toString(),
                        name: name != (provider['name']?.toString() ?? '') ? name : null,
                        providerType:
                            providerType != (provider['provider_type']?.toString() ?? '')
                                ? providerType
                                : null,
                        baseUrl: baseUrl != (provider['base_url']?.toString() ?? '')
                            ? baseUrl
                            : null,
                        apiKey: apiKey,
                        defaultModel:
                            model != (provider['default_model']?.toString() ?? '') ? model : null,
                        enabled: enabled != (provider['enabled'] != false) ? enabled : null,
                      );
                    } else {
                      await AuthService.createAiProvider(
                        name: name,
                        providerType: providerType,
                        baseUrl: baseUrl,
                        apiKey: apiKey,
                        defaultModel: model,
                        enabled: enabled,
                      );
                    }
                    if (!dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                    if (!mounted) return;
                    NotifyUtils.showNotify(context, t.msgProviderSaved);
                    await _loadProviders();
                  } catch (e) {
                    if (!dialogContext.mounted) return;
                    NotifyUtils.showNotify(dialogContext, e.toString());
                  }
                },
                child: Text(t.actionSaveProvider),
              );
            }

            return AlertDialog(
              title: Text(isEdit ? t.actionEdit : t.actionAddProvider),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        key: const ValueKey('ai-provider-name-field'),
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: t.labelProviderName,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty) ? t.msgNameRequired : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: providerType,
                        decoration: InputDecoration(
                          labelText: t.labelProviderType,
                          border: const OutlineInputBorder(),
                        ),
                        items: const ['deepseek', 'openai', 'custom']
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(
                                  type == 'deepseek'
                                      ? t.labelProviderTypeDeepseek
                                      : type == 'openai'
                                          ? t.labelProviderTypeOpenai
                                          : t.labelProviderTypeCustom,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            providerType = value;
                            final preset = _presetFor(value);
                            if (preset != null && !isEdit) {
                              baseUrlController.text = preset.$1;
                              modelController.text = preset.$2;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('ai-provider-base-url-field'),
                        controller: baseUrlController,
                        decoration: InputDecoration(
                          labelText: t.labelBaseUrl,
                          hintText: t.hintBaseUrl,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final v = (value ?? '').trim();
                          if (v.isEmpty) return t.msgBaseUrlRequired;
                          if (!v.startsWith('http://') && !v.startsWith('https://')) {
                            return t.msgBaseUrlInvalid;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('ai-provider-api-key-field'),
                        controller: apiKeyController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: t.labelApiKey,
                          hintText: isEdit ? t.hintApiKeyKeep : t.hintApiKeyNew,
                          border: const OutlineInputBorder(),
                        ),
                        validator: isEdit
                            ? null
                            : (value) =>
                                (value == null || value.trim().isEmpty) ? t.labelApiKey : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('ai-provider-model-field'),
                        controller: modelController,
                        decoration: InputDecoration(
                          labelText: t.labelDefaultModel,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      // 编辑模式：通过 OpenAI 兼容 /models API 拉取模型列表选择
                      if (isEdit)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              key: const ValueKey('ai-provider-fetch-models-button'),
                              onPressed: fetchingModels
                                  ? null
                                  : () => fetchModels(dialogContext, setDialogState),
                              icon: fetchingModels
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(RemixIcon.download2Line, size: 18),
                              label: Text(
                                fetchingModels ? t.msgFetchingModels : t.actionFetchModels,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t.labelEnabled),
                        value: enabled,
                        onChanged: (value) => setDialogState(() => enabled = value),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(t.actionCancel),
                ),
                Builder(builder: (context) => buildSaveButton()),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(t.titleAiProviders)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showProviderForm(),
        child: const Icon(RemixIcon.addLine),
      ),
      body: _isLoading
          ? const LoadingView()
          : _loadError != null
              ? ErrorView(
                  message: _loadError!,
                  onRetry: _loadProviders,
                  retryLabel: t.msgRetry,
                )
              : _providers.isEmpty
                  ? EmptyView(
                      icon: RemixIcon.openaiLine,
                      message: t.msgNoAiProviders,
                      actionLabel: t.actionAddProvider,
                      onAction: () => _showProviderForm(),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadProviders,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                        itemCount: _providers.length,
                        itemBuilder: (context, index) {
                          final provider =
                              Map<String, dynamic>.from(_providers[index]);
                          final type = provider['provider_type']?.toString() ?? 'custom';
                          final keyConfigured = provider['api_key_configured'] == true;
                          final enabledProvider = provider['enabled'] != false;

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: colorScheme.primaryContainer,
                                child: Icon(
                                  RemixIcon.openaiLine,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                              title: Text(
                                provider['name']?.toString() ?? '',
                                style: textTheme.titleMedium,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(provider['base_url']?.toString() ?? ''),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      _TypeChip(
                                        label: _providerTypeLabel(t, type),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        keyConfigured
                                            ? t.labelKeyConfigured
                                            : t.labelKeyNotConfigured,
                                        style: textTheme.bodySmall?.copyWith(
                                          color: keyConfigured
                                              ? colorScheme.primary
                                              : colorScheme.error,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if ((provider['default_model']?.toString() ?? '').isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        '${t.labelDefaultModel}: '
                                        '${provider['default_model']}',
                                        style: textTheme.bodySmall,
                                      ),
                                    ),
                                  if (!enabledProvider)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Row(
                                        children: [
                                          Icon(
                                            RemixIcon.pauseCircleLine,
                                            size: 14,
                                            color: colorScheme.error,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            t.labelEnabled,
                                            style: textTheme.bodySmall?.copyWith(
                                              color: colorScheme.error,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(RemixIcon.more2Line),
                                onPressed: () => _showActions(provider),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

/// 供应商类型小徽章。
class _TypeChip extends StatelessWidget {
  final String label;

  const _TypeChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: colorScheme.onSecondaryContainer),
      ),
    );
  }
}
