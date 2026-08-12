import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/models/ai_provider_presets.dart';
import 'package:mobile_portainer_flutter_module/services/auth_service.dart';
import 'package:mobile_portainer_flutter_module/utils/notify_utils.dart';
import 'package:mobile_portainer_flutter_module/widgets/action_sheet.dart';
import 'package:mobile_portainer_flutter_module/widgets/empty_view.dart';
import 'package:mobile_portainer_flutter_module/widgets/error_view.dart';
import 'package:mobile_portainer_flutter_module/widgets/loading_view.dart';

/// AI API 供应商配置页 — 纯配置存储，为后续 AI 功能做准备。
///
/// 支持：添加 / 编辑 / 删除供应商，测试连接（验证 Base URL 与 API Key），
/// 内置 70+ 个预设供应商（参考 cc-switch，选择后自动填充名称 / Base URL
/// 与默认模型，并展示对应 logo）。
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

  /// 按类型标识查找预设（73 个预设来自 cc-switch 整理）。
  AiProviderPreset? _presetByType(String type) {
    for (final preset in aiProviderPresets) {
      if (preset.type == type) return preset;
    }
    return null;
  }

  String _providerTypeLabel(AppLocalizations t, String type) {
    final preset = _presetByType(type);
    if (preset != null) return preset.name;
    return t.labelProviderTypeCustom;
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
    // 默认模型：新增模式 / 拉取失败或空列表的兜底手动输入用
    final modelController = TextEditingController(
      text: isEdit ? (provider['default_model']?.toString() ?? '') : 'deepseek-chat',
    );
    // 编辑模式：打开表单自动拉取模型列表，默认模型改为下拉选择
    var selectedModel = isEdit ? (provider['default_model']?.toString() ?? '') : null;
    var modelsLoading = false;
    var modelsFetchError = '';
    List<Map<String, dynamic>>? modelList; // null = 尚未拉取成功
    var modelsAutoLoadStarted = false;
    var enabled = isEdit ? provider['enabled'] != false : true;

    /// 通过后端代理请求 {base_url}/models 获取模型列表，供默认模型下拉选择。
    ///
    /// - 编辑模式：打开表单自动调用一次（使用已存储的 Key）；
    /// - 新增模式：点击「获取模型列表」手动触发（manual=true），使用表单中
    ///   临时填写的 base_url + api_key 经后端预览端点拉取（Key 不落库）。
    Future<void> loadModels(BuildContext dialogContext, StateSetter setDialogState,
        {bool manual = false}) async {
      final t = AppLocalizations.of(dialogContext)!;
      if (!manual && modelsAutoLoadStarted) return;
      modelsAutoLoadStarted = true;
      setDialogState(() {
        modelsLoading = true;
        modelsFetchError = '';
      });
      try {
        final result = isEdit
            ? await AuthService.getAiProviderModels(id: provider['id'].toString())
            : await AuthService.previewAiProviderModels(
                baseUrl: baseUrlController.text.trim(),
                apiKey: apiKeyController.text.trim(),
              );
        if (!dialogContext.mounted) return;
        setDialogState(() {
          modelsLoading = false;
          if (result['ok'] != true) {
            // ok=false 时展示后端返回的人类可读失败原因
            modelsFetchError =
                result['message']?.toString() ?? t.msgModelsFetchFailed('未知错误');
          } else {
            final list = (result['models'] as List? ?? const [])
                .map((m) => Map<String, dynamic>.from(m))
                .toList();
            // 新增模式预选值：手动输入的模型在列表中则选中它，否则选首项，
            // 保证切换为下拉后始终有选中项（编辑模式已按当前默认模型初始化）。
            if (!isEdit && selectedModel == null) {
              final typed = modelController.text.trim();
              final typedInList = list.any((m) => m['id']?.toString() == typed);
              if (typedInList) {
                selectedModel = typed;
              } else if (list.isNotEmpty) {
                selectedModel = list.first['id']?.toString();
              }
            }
            modelList = list;
          }
        });
      } catch (e) {
        if (!dialogContext.mounted) return;
        setDialogState(() {
          modelsLoading = false;
          modelsFetchError = t.msgModelsFetchFailed(e.toString());
        });
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final colorScheme = Theme.of(dialogContext).colorScheme;

            // 编辑模式：对话框打开后自动拉取一次模型列表（标志位防重复触发）
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!modelsAutoLoadStarted && isEdit) {
                loadModels(dialogContext, setDialogState);
              }
            });

            /// 默认模型手动输入框（新增模式 / 拉取失败或空列表时兜底）。
            Widget buildModelManualField(AppLocalizations t) {
              return TextFormField(
                key: const ValueKey('ai-provider-model-field'),
                controller: modelController,
                decoration: InputDecoration(
                  labelText: t.labelDefaultModel,
                  border: const OutlineInputBorder(),
                ),
              );
            }

            /// 新增模式默认模型区域：手动输入 + 「获取模型列表」按钮。
            ///
            /// 点击后按表单中填写的 base_url + api_key 经后端预览端点拉取模型
            /// 列表；成功后默认模型切换为下拉选择。信息未填全时点击给提示。
            Widget buildModelManualWithFetchButton(
              StateSetter setDialogState,
              AppLocalizations t,
            ) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildModelManualField(t),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    key: const ValueKey('ai-provider-fetch-models-button'),
                    onPressed: () {
                      // 实时读取输入值（controller 变化不触发 rebuild，不能在 build 时缓存判断）
                      if (baseUrlController.text.trim().isEmpty ||
                          apiKeyController.text.trim().isEmpty) {
                        NotifyUtils.showNotify(dialogContext, t.msgFetchModelsNeedInfo);
                        return;
                      }
                      loadModels(dialogContext, setDialogState, manual: true);
                    },
                    icon: const Icon(RemixIcon.refreshLine, size: 16),
                    label: Text(t.actionFetchModels),
                  ),
                ],
              );
            }

            /// 默认模型下拉选择框：选项来自 API 模型列表。
            ///
            /// 当前默认模型不在列表中时作为首项保留（带「（当前）」标识），避免保存时丢失。
            Widget buildModelDropdown(
              StateSetter setDialogState,
              AppLocalizations t,
            ) {
              final options = <String, String>{}; // id -> label，保持模型列表顺序
              for (final m in modelList!) {
                final id = m['id']?.toString() ?? '';
                final name = m['name']?.toString() ?? '';
                if (id.isEmpty) continue;
                options[id] = name.isNotEmpty ? name : id;
              }
              final currentModel = provider?['default_model']?.toString() ?? '';
              if (isEdit && currentModel.isNotEmpty && !options.containsKey(currentModel)) {
                options[currentModel] = '$currentModel${t.labelModelCurrent}';
              }
              return DropdownButtonFormField<String>(
                key: const ValueKey('ai-provider-model-dropdown'),
                initialValue: selectedModel,
                decoration: InputDecoration(
                  labelText: t.labelDefaultModel,
                  border: const OutlineInputBorder(),
                ),
                items: options.entries
                    .map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => selectedModel = value);
                },
              );
            }

            Widget buildSaveButton() {
              return FilledButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;

                  final name = nameController.text.trim();
                  final baseUrl = baseUrlController.text.trim();
                  final apiKey = apiKeyController.text.trim();
                  // 模型列表可用（成功拉取且非空）时取下拉选中值，否则取手动输入框的值
                  final useDropdown = modelList != null &&
                      modelList!.isNotEmpty &&
                      modelsFetchError.isEmpty;
                  final model =
                      useDropdown ? (selectedModel ?? '') : modelController.text.trim();

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
                        items: [
                          // 73 个预设：显示 logo + 名称，选择后自动填充
                          ...aiProviderPresets.map(
                            (preset) => DropdownMenuItem(
                              value: preset.type,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _ProviderLogo(
                                    logo: preset.logo,
                                    size: 20,
                                    fallbackIcon: RemixIcon.openaiLine,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      preset.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 自定义：完全手动填写
                          DropdownMenuItem(
                            value: 'custom',
                            child: Row(
                              children: [
                                Icon(
                                  RemixIcon.settings4Line,
                                  size: 20,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 8),
                                Text(t.labelProviderTypeCustom),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            providerType = value;
                            final preset = _presetByType(value);
                            if (preset != null) {
                              // 预设：填充名称 / Base URL / 默认模型
                              nameController.text = preset.name;
                              baseUrlController.text = preset.baseUrl;
                              modelController.text = preset.defaultModel;
                            } else {
                              // 自定义：清空自动填充值，完全手动填写
                              nameController.text = '';
                              baseUrlController.text = '';
                              modelController.text = '';
                            }
                            // 切换类型会改动 base_url，之前拉取的
                            // 模型列表与下拉选中作废，等待重新拉取
                            if (modelList != null) {
                              modelList = null;
                              selectedModel = null;
                              modelsFetchError = '';
                              modelsLoading = false;
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
                      // 默认模型：编辑模式自动拉取模型列表后下拉选择；加载中/失败/空列表有对应状态
                      if (modelsLoading)
                        Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text(t.msgFetchingModels),
                          ],
                        )
                      else if (modelsFetchError.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              modelsFetchError,
                              style: Theme.of(dialogContext)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: colorScheme.error),
                            ),
                            TextButton(
                              key: const ValueKey('ai-provider-models-retry-button'),
                              onPressed: () =>
                                  loadModels(dialogContext, setDialogState, manual: true),
                              child: Text(t.msgRetry),
                            ),
                            buildModelManualField(t),
                          ],
                        )
                      else if (modelList != null && modelList!.isEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.msgNoModelsFound,
                              style: Theme.of(dialogContext)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: colorScheme.error),
                            ),
                            buildModelManualField(t),
                          ],
                        )
                      else if (modelList != null)
                        buildModelDropdown(setDialogState, t)
                      else if (isEdit)
                        // 编辑模式首帧兜底：自动拉取尚未开始，先显示手动输入
                        buildModelManualField(t)
                      else
                        // 新增模式：手动输入 + 「获取模型列表」按钮（点击后转下拉）
                        buildModelManualWithFetchButton(setDialogState, t),
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

                          final preset = _presetByType(type);

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: colorScheme.primaryContainer,
                                child: preset != null
                                    ? _ProviderLogo(
                                        logo: preset.logo,
                                        size: 32,
                                        fallbackIcon: RemixIcon.openaiLine,
                                        fallbackColor:
                                            colorScheme.onPrimaryContainer,
                                      )
                                    : Icon(
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

/// 供应商 logo 图片（assets/images/provider_logos/ 目录下 logo 字段 + .png）。
///
/// 资源缺失或加载失败时回退到指定图标，保证列表与下拉框始终可渲染。
class _ProviderLogo extends StatelessWidget {
  final String logo;
  final double size;
  final IconData fallbackIcon;
  final Color? fallbackColor;

  const _ProviderLogo({
    required this.logo,
    required this.size,
    required this.fallbackIcon,
    this.fallbackColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipOval(
      child: Image.asset(
        'assets/images/provider_logos/$logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Icon(
          fallbackIcon,
          size: size,
          color: fallbackColor ?? colorScheme.onSurfaceVariant,
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
