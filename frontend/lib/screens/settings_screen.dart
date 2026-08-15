import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/screens/qr_scan_screen.dart';
import 'package:mobile_portainer_flutter_module/screens/backup_screen.dart';
import 'package:mobile_portainer_flutter_module/utils/copy_helper.dart';
import 'package:mobile_portainer_flutter_module/screens/ai_providers_screen.dart';
import 'package:mobile_portainer_flutter_module/screens/agent_debug_logs_screen.dart';
import 'package:mobile_portainer_flutter_module/screens/email_settings_screen.dart';
import 'package:mobile_portainer_flutter_module/screens/profile_settings_screen.dart';
import 'package:mobile_portainer_flutter_module/utils/notify_utils.dart';
import 'package:mobile_portainer_flutter_module/utils/api_error_handler.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';
import '../main.dart';

import 'package:mobile_portainer_flutter_module/services/update_service.dart';
import '../services/auth_service.dart';
import '../services/connect_service.dart';
import '../services/docker_service.dart';
import '../services/server_list_storage.dart';
import '../services/harmonyos_platform.dart';
import '../services/harmonyos_shared_prefs.dart';
import '../utils/platform_detector.dart';
import '../utils/platform_dialogs.dart';
import '../utils/mixed_content_check.dart';
import '../widgets/loading_view.dart';
import '../widgets/bottom_nav_bar_spacer.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onSaved;
  /// CI 构建时间（frontend:build_web 通过 --dart-define=BUILD_TIME 注入）。
  /// 本地开发构建无该 define 时为空字符串，页面隐藏构建时间行。
  final String buildTime;
  const SettingsScreen({
    super.key,
    this.onSaved,
    this.buildTime = const String.fromEnvironment('BUILD_TIME'),
  });

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;
  String _currentLanguage = 'system';
  String _currentTimezone = 'system';
  String _versionText = '';

  // Server Management
  List<Map<String, String>> _servers = [];
  String? _activeApiUrl;
  String? _webBackendUrl;

  // API Key Management
  List<Map<String, dynamic>> _apiKeys = [];
  bool _isLoadingKeys = true;
  String? _apiKeyError;
  final Set<int> _visibleApiKeys = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadVersion();
    if (PlatformDetector.isWeb) {
      _loadApiKeys();
    }
  }

  void refresh() {
    _loadSettings();
  }

  Future<dynamic> _getPrefs() async {
    if (PlatformDetector.isOhos) {
      return HarmonyosPreferences.getInstance();
    }
    return SharedPreferences.getInstance();
  }

  Future<void> _loadSettings() async {
    final prefs = await _getPrefs();
    final languageCode = await prefs.getString('language_code');
    final timezoneCode = await prefs.getString('timezone_code');
    final activeApiUrl = await prefs.getString('docker_api_url');

    // Web 端服务器列表存后端数据库（跨 origin 共享），原生端存本地；
    // 未登录或后端不可达时自动回退本地缓存
    final loadedServers = await ServerListStorage().load();

    String? apiKey;
    if (loadedServers.isEmpty && activeApiUrl != null && activeApiUrl.isNotEmpty) {
      apiKey = await prefs.getString('docker_api_key');
    }

    String? webBackendUrl;
    if (PlatformDetector.isWeb) {
      webBackendUrl = await prefs.getString('docker_auth_server_url');
    }

    setState(() {
      _currentLanguage = languageCode ?? 'system';
      _currentTimezone = timezoneCode ?? 'system';
      _activeApiUrl = activeApiUrl;
      _webBackendUrl = webBackendUrl;
      _servers = loadedServers;

      if (_servers.isEmpty && _activeApiUrl != null && _activeApiUrl!.isNotEmpty) {
        _servers.add({
          'name': 'Default Server',
          'url': _activeApiUrl!,
          'apiKey': apiKey ?? '',
        });
      }

      _isLoading = false;
    });

    if (_servers.isNotEmpty && _servers.length == 1) {
      await _saveServerList();
    }
  }

  Future<void> _loadVersion() async {
    if (PlatformDetector.isOhos) {
      final info = await HarmonyosPlatform.getPackageInfo();
      if (!mounted) return;
      setState(() {
        _versionText = '${info['version']}+${info['buildNumber']}';
      });
      return;
    }
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _versionText = '${info.version}+${info.buildNumber}';
    });
  }

  Future<void> _saveServerList() async {
    await ServerListStorage().save(_servers);
  }

  Future<void> _updateTimezone(String? newValue) async {
    if (newValue == null) return;
    setState(() {
      _currentTimezone = newValue;
    });
    final prefs = await _getPrefs();
    await prefs.setString('timezone_code', newValue);
    if (widget.onSaved != null) widget.onSaved!();
  }

  Future<void> _checkUpdate() async {
    await UpdateService.checkUpdate(context, showNoUpdateToast: true);
  }

  Future<void> _openApiDocs() async {
    if (_activeApiUrl == null || _activeApiUrl!.isEmpty) {
      if (mounted) {
        NotifyUtils.showNotify(context, AppLocalizations.of(context)!.msgNoActiveServer);
      }
      return;
    }
    final apiUri = Uri.parse(_activeApiUrl!);
    final docsUrl = Uri(
      scheme: apiUri.scheme,
      host: apiUri.host,
      port: apiUri.port,
      path: '/docs',
    );
    bool launched;
    if (PlatformDetector.isOhos) {
      launched = await HarmonyosPlatform.launchUrl(docsUrl.toString());
    } else {
      launched = await launchUrl(docsUrl, mode: LaunchMode.externalApplication);
    }
    if (!launched) {
      if (mounted) {
        NotifyUtils.showNotify(context, 'Could not launch API Docs');
      }
    }
  }

  Future<void> _openRedoc() async {
    if (_activeApiUrl == null || _activeApiUrl!.isEmpty) {
      if (mounted) {
        NotifyUtils.showNotify(context, AppLocalizations.of(context)!.msgNoActiveServer);
      }
      return;
    }
    final apiUri = Uri.parse(_activeApiUrl!);
    final docsUrl = Uri(
      scheme: apiUri.scheme,
      host: apiUri.host,
      port: apiUri.port,
      path: '/redoc',
    );
    bool launched;
    if (PlatformDetector.isOhos) {
      launched = await HarmonyosPlatform.launchUrl(docsUrl.toString());
    } else {
      launched = await launchUrl(docsUrl, mode: LaunchMode.externalApplication);
    }
    if (!launched) {
      if (mounted) {
        NotifyUtils.showNotify(context, 'Could not launch ReDoc');
      }
    }
  }

  Future<void> _openGithub() async {
    final Uri url = Uri.parse('https://github.com/CodeFuckee/mobile_portainer_flutter_module');
    bool launched;
    if (PlatformDetector.isOhos) {
      launched = await HarmonyosPlatform.launchUrl(url.toString());
    } else {
      launched = await launchUrl(url, mode: LaunchMode.externalApplication);
    }
    if (!launched) {
      if (mounted) {
        NotifyUtils.showNotify(context, 'Could not launch GitHub');
      }
    }
  }

  void _onLanguageChanged(String? newValue) async {
    if (newValue == null) return;
    setState(() {
      _currentLanguage = newValue;
    });

    Locale? newLocale;
    if (newValue == 'en') {
      newLocale = const Locale('en');
    } else if (newValue == 'zh') {
      newLocale = const Locale('zh');
    }

    MyApp.setLocale(context, newLocale);

    final prefs = await _getPrefs();
    await prefs.setString('language_code', newValue);
  }

  Future<void> _switchServer(Map<String, String> server) async {
    final t = AppLocalizations.of(context)!;
    final prefs = await _getPrefs();
    await prefs.setString('docker_api_url', server['url']!);
    await prefs.setString('docker_api_key', server['apiKey'] ?? '');
    await prefs.setString('docker_ignore_ssl', server['ignoreSsl'] ?? 'false');
    // 同步 Web 端认证凭据，避免切换后设置页 API Key 管理仍指向旧服务器
    await prefs.setString('docker_auth_server_url', server['url']!);
    await prefs.setString('docker_auth_token', server['apiKey'] ?? '');

    setState(() {
      _activeApiUrl = server['url'];
    });

    if (mounted) {
      NotifyUtils.showNotify(context, t.msgServerSwitched(server['name']!));
    }

    if (widget.onSaved != null) {
      widget.onSaved!();
    }
  }

  /// 测试服务器连接：调用 /info 接口验证 url 与 API Key 是否有效。
  /// 返回 null 表示连接成功，否则返回错误描述。
  Future<String?> _testConnection(String url, String apiKey, bool ignoreSsl) async {
    final cleanUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    try {
      final service = DockerService(baseUrl: cleanUrl, apiKey: apiKey, ignoreSsl: ignoreSsl);
      await service.getSystemInfo();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> _copyServer(int index) async {
    final t = AppLocalizations.of(context)!;
    final server = _servers[index];

    final newServer = Map<String, String>.from(server);
    newServer['name'] = '${server['name']} - Copy';

    setState(() {
      _servers.add(newServer);
    });

    await _saveServerList();

    if (mounted) {
      NotifyUtils.showNotify(context, t.msgServerCopied);
    }
  }

  Future<void> _deleteServer(int index) async {
    final server = _servers[index];
    final isDeletingActive = server['url'] == _activeApiUrl;

    setState(() {
      _servers.removeAt(index);
    });

    final prefs = await _getPrefs();
    await _saveServerList();

    if (isDeletingActive) {
      if (_servers.isNotEmpty) {
        _switchServer(_servers.first);
      } else {
        await prefs.remove('docker_api_url');
        await prefs.remove('docker_api_key');
        await prefs.remove('docker_ignore_ssl');
        setState(() {
          _activeApiUrl = null;
        });
      }
    }

    if (mounted) {
      final t = AppLocalizations.of(context)!;
      NotifyUtils.showNotify(context, t.msgServerDeleted);
    }
  }

  void _showAddServerOptions() {
    final t = AppLocalizations.of(context)!;
    PlatformDialogs.showActionMenu(
      context: context,
      content: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 网页授权添加:Web 与移动端(Android/iOS/鸿蒙)均支持;
            // 桌面端无深链基建,保持隐藏
            if (kIsWeb ||
                PlatformDetector.isAndroid ||
                PlatformDetector.isIOS ||
                PlatformDetector.isOhos)
              ListTile(
                leading: const Icon(RemixIcon.linksLine),
                title: Text(t.buttonConnectAdd),
                onTap: () {
                  Navigator.pop(context);
                  // 菜单退场动画未完成时立即 showDialog,语义树模式下
                  // 新对话框会被吞掉(route 动画竞争,偶发)。延迟到
                  // 下一帧再打开,避免对话框打开失败。
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) showConnectAddDialog();
                  });
                },
              ),
            ListTile(
              leading: const Icon(RemixIcon.qrScanLine),
              title: Text(t.buttonScanQr),
              onTap: () async {
                Navigator.pop(context);
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const QrScanScreen(),
                  ),
                );
                if (result != null && result is String && mounted) {
                  _processQrResult(result);
                }
              },
            ),
            ListTile(
              leading: const Icon(RemixIcon.editLine),
              title: Text(t.buttonManualInput),
              onTap: () {
                Navigator.pop(context);
                // 与网页授权添加相同的时序处理:菜单退场动画期间
                // 立即 showDialog 偶发被吞,延迟到下一帧打开。
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _showServerDialog();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 网页授权添加服务器(Web 端 /connect 流程)。
  ///
  /// 输入目标服务器 URL → 探测能力 → 确认跳转 → 目标服务器授权页
  /// 登录/确认后自动回跳,由 main.dart 完成 token 交换并添加服务器。
  /// 探测失败(老版本部署/裸 API)回退手动输入,不静默降级。
  ///
  /// [sourceIsHttpsOverride] 仅供测试注入 https 源场景(flutter test 中
  /// kIsWeb 恒为 false,真实 Web 分支无法走到),为空时保持线上判定。
  void showConnectAddDialog({bool? sourceIsHttpsOverride}) {
    final t = AppLocalizations.of(context)!;
    final urlController = TextEditingController(text: 'http://');
    bool isProbing = false;
    bool isProbed = false;
    bool isProbeFailed = false;
    String? authorizeUrl;
    String? errorMessage;
    // mixed content 提前提示:https 源页面 + http 目标会被浏览器阻止,
    // 探测必然失败。对话框默认预填 http://,https 源下打开即提示,
    // 用户改为 https 目标后自动恢复。
    final bool sourceIsHttps = sourceIsHttpsOverride ??
        (kIsWeb && Uri.base.scheme.toLowerCase() == 'https');
    // 提示状态用 ValueNotifier 局部更新(提示条/按钮禁用态)。
    // 注意:Web 端(CanvasKit)提示条的挂载/卸载会触发引擎失焦 bug,
    // 因此提示条采用固定高度占位 + Opacity 显隐(子树恒挂载),
    // 输入过程中 TextField 不重建、提示条不卸载,可连续输入(issue #19)。
    final mixedContentNotifier = ValueNotifier<bool>(
      isMixedContentTarget(
        urlController.text,
        sourceIsHttps: sourceIsHttps,
      ),
    );
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) {
          final colorScheme = Theme.of(dialogContext).colorScheme;
          final textTheme = Theme.of(dialogContext).textTheme;

          return AlertDialog(
            title: Row(
              children: [
                // 标题图标容器:primaryContainer 圆角块,与页面信息块风格一致
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    RemixIcon.linksLine,
                    size: 20,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(t.titleConnectAdd)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 探测失败 / 注册失败:对话框内错误条,不再打断流程
                  if (errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            RemixIcon.errorWarningLine,
                            size: 20,
                            color: colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: TextStyle(
                                color: colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (!isProbed) ...[
                    TextField(
                      controller: urlController,
                      autofocus: true,
                      style: TextStyle(color: colorScheme.onSurface),
                      onChanged: (value) => mixedContentNotifier.value =
                          isMixedContentTarget(
                        value,
                        sourceIsHttps: sourceIsHttps,
                      ),
                      decoration: InputDecoration(
                        labelText: t.labelDockerApiUrl,
                        hintText: t.hintIpPort,
                        prefixIcon: const Icon(RemixIcon.serverLine),
                        helperText: t.helperConnectAdd,
                      ),
                    ),
                    // mixed content 提示:固定高度占位 + Opacity 显隐,
                    // 提示条子树恒挂载(从不卸载)——Web 端提示条的挂载/卸载
                    // 会触发引擎失焦 bug,导致输入框无法连续输入(issue #19)。
                    SizedBox(
                      // 提示条最大高度(padding 12*2 + 文本 3 行),恒定占位
                      height: 78,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: mixedContentNotifier,
                        builder: (context, isMixed, _) => Opacity(
                          opacity: isMixed ? 1.0 : 0.0,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    RemixIcon.errorWarningLine,
                                    size: 20,
                                    color: colorScheme.onErrorContainer,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      t.errorConnectMixedContent,
                                      maxLines: 3,
                                      style: TextStyle(
                                        color: colorScheme.onErrorContainer,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (isProbing) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(t.msgConnectProbing, style: textTheme.bodySmall),
                    ],
                  ] else ...[
                    // 探测成功:primaryContainer 卡片展示目标服务器与跳转说明
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            RemixIcon.linksLine,
                            size: 20,
                            color: colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  urlController.text.trim(),
                                  style: TextStyle(
                                    color: colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  t.helperConnectAdd,
                                  style: TextStyle(
                                    color: colorScheme.onPrimaryContainer,
                                    fontSize: 12,
                                  ),
                                ),
                                // 移动端:提示将打开系统浏览器,授权完成后自动回跳
                                if (!kIsWeb) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    t.msgConnectLaunchHint,
                                    style: TextStyle(
                                      color: colorScheme.onPrimaryContainer,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isProbing ? null : () => Navigator.pop(dialogContext),
                child: Text(t.actionCancel),
              ),
              if (isProbeFailed)
                // 老版本部署/裸 API:回退手动输入,预填 URL
                FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    if (!mounted) return;
                    _showServerDialog(
                        server: {'url': urlController.text.trim()});
                  },
                  child: Text(t.buttonManualInput),
                )
              else if (isProbed)
                FilledButton.icon(
                  icon: const Icon(RemixIcon.externalLinkLine, size: 18),
                  label: Text(t.actionConfirm),
                  onPressed: () {
                    final authUrl = authorizeUrl;
                    if (authUrl == null) return;
                    Navigator.pop(dialogContext);
                    ConnectService.redirectTo(authUrl);
                  },
                )
              else
                ValueListenableBuilder<bool>(
                  valueListenable: mixedContentNotifier,
                  builder: (context, isMixed, _) => FilledButton(
                    onPressed: (isProbing || isMixed)
                        ? null
                        : () async {
                            final url = urlController.text.trim();
                            if (url.isEmpty) return;

                            // 第一步:探测目标服务器是否支持 /connect 流程
                            setStateDialog(() {
                              isProbing = true;
                              errorMessage = null;
                            });
                            final supported =
                                await ConnectService.probe(url);
                            if (!dialogContext.mounted) return;
                            if (!supported) {
                              setStateDialog(() {
                                isProbing = false;
                                isProbeFailed = true;
                                errorMessage = t.msgConnectProbeFailed;
                              });
                              return;
                            }
                            // 注册 public client 并构造授权页地址
                            try {
                              final authUrl = await ConnectService
                                  .buildAuthorizeUrl(url);
                              if (!dialogContext.mounted) return;
                              setStateDialog(() {
                                isProbing = false;
                                isProbed = true;
                                authorizeUrl = authUrl;
                              });
                            } catch (e) {
                              if (dialogContext.mounted) {
                                setStateDialog(() {
                                  isProbing = false;
                                  errorMessage = t.msgConnectFailed(
                                      e.toString());
                                });
                              }
                            }
                          },
                    child: Text(t.actionContinue),
                  ),
                ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      urlController.dispose();
      mixedContentNotifier.dispose();
    });
  }

  void _processQrResult(String result) {
    final t = AppLocalizations.of(context)!;
    try {
      final data = jsonDecode(result);
      if (data is Map) {
        String? url;
        String? apiKey;

        if (data.containsKey('url')) {
          url = data['url'];
        }
        if (data.containsKey('apikey')) {
          apiKey = data['apikey'];
        } else if (data.containsKey('apiKey')) {
          apiKey = data['apiKey'];
        }

        if (url != null || apiKey != null) {
          _showServerDialog(
            server: {
              'url': url ?? '',
              'apiKey': apiKey ?? '',
            },
          );
          NotifyUtils.showNotify(context, t.msgScanSuccess);
        }
      }
    } catch (e) {
      NotifyUtils.showNotify(context, t.msgInvalidQr);
    }
  }

  void _showServerDialog({Map<String, String>? server, int? index}) {
    final t = AppLocalizations.of(context)!;
    final nameController = TextEditingController(text: server?['name'] ?? '');
    final urlController = TextEditingController(text: server?['url'] ?? 'http://');
    final apiKeyController = TextEditingController(text: server?['apiKey'] ?? '');
    bool ignoreSsl = server?['ignoreSsl'] == 'true';
    bool isApiKeyVisible = false;
    bool isTestingConnection = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text(server == null || index == null ? t.buttonAddServer : t.actionEdit),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                    decoration: InputDecoration(
                      labelText: t.labelServerName,
                      hintText: 'My Home Server',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: urlController,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                    decoration: InputDecoration(
                      labelText: t.labelDockerApiUrl,
                      hintText: t.hintIpPort,
                      helperText: t.helperDockerApiUrl,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: apiKeyController,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                    decoration: InputDecoration(
                      labelText: t.labelApiKey,
                      hintText: t.hintApiKey,
                      suffixIcon: IconButton(
                        icon: Icon(
                          isApiKeyVisible ? RemixIcon.eyeLine : RemixIcon.eyeOffLine,
                        ),
                        onPressed: () {
                          setStateDialog(() {
                            isApiKeyVisible = !isApiKeyVisible;
                          });
                        },
                      ),
                    ),
                    obscureText: !isApiKeyVisible,
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: Text(t.labelIgnoreSsl),
                    value: ignoreSsl,
                    onChanged: (bool value) {
                      setStateDialog(() {
                        ignoreSsl = value;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: isTestingConnection
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(RemixIcon.link, size: 18),
                      label: Text(t.buttonTestConnection),
                      onPressed: isTestingConnection
                          ? null
                          : () async {
                              if (urlController.text.trim().isEmpty) {
                                NotifyUtils.showNotify(context, t.helperDockerApiUrl);
                                return;
                              }
                              if (apiKeyController.text.trim().isEmpty) {
                                NotifyUtils.showNotify(context, t.msgApiKeyRequired);
                                return;
                              }
                              setStateDialog(() => isTestingConnection = true);
                              final error = await _testConnection(
                                urlController.text.trim(),
                                apiKeyController.text.trim(),
                                ignoreSsl,
                              );
                              setStateDialog(() => isTestingConnection = false);
                              if (!context.mounted) return;
                              NotifyUtils.showNotify(
                                context,
                                error == null
                                    ? t.msgConnectionSuccess
                                    : t.msgConnectionFailed(error),
                              );
                            },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t.actionCancel),
              ),
              TextButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  final url = urlController.text.trim();
                  final apiKey = apiKeyController.text.trim();

                  if (name.isEmpty || url.isEmpty) {
                    return;
                  }
                  if (apiKey.isEmpty) {
                    NotifyUtils.showNotify(context, t.msgApiKeyRequired);
                    return;
                  }

                  final newServer = {
                    'name': name,
                    'url': url,
                    'apiKey': apiKey,
                    'ignoreSsl': ignoreSsl.toString(),
                  };

                  setState(() {
                    if (index != null) {
                      _servers[index] = newServer;
                      if (_activeApiUrl == server?['url']) {
                        _switchServer(newServer);
                      }
                    } else {
                      _servers.add(newServer);
                      if (_servers.length == 1) {
                        _switchServer(newServer);
                      }
                    }
                  });

                  await _saveServerList();

                  if (context.mounted) {
                    Navigator.pop(context);
                    NotifyUtils.showNotify(context, index != null ? t.msgServerUpdated : t.msgServerAdded);
                  }
                },
                child: Text(t.buttonSave),
              ),
            ],
        );
        },
      ),
    ).whenComplete(() {
      nameController.dispose();
      urlController.dispose();
      apiKeyController.dispose();
    });
  }

  String _maskUrl(String url) {
    if (url.isEmpty) return '';
    try {
      final uri = Uri.parse(url);
      String host = uri.host;
      if (host.isEmpty) return url;

      String maskedHost = host;
      if (host.length > 5) {
        maskedHost = '${host.substring(0, 3)}****${host.substring(host.length - 2)}';
      } else {
        maskedHost = '****';
      }

      return url.replaceFirst(host, maskedHost);
    } catch (_) {
      return url;
    }
  }

  // --- API Key Management ---

  Future<void> _loadApiKeys() async {
    setState(() {
      _isLoadingKeys = true;
      _apiKeyError = null;
    });

    try {
      final keys = await AuthService.getApiKeys();
      if (!mounted) return;
      setState(() {
        _apiKeys = keys;
        _isLoadingKeys = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        ApiErrorHandler.show(context, e);
        _apiKeyError = e.toString();
        _isLoadingKeys = false;
      });
    }
  }

  Future<void> _createApiKey() async {
    final t = AppLocalizations.of(context)!;
    final nameController = TextEditingController();
    final keyController = TextEditingController();

    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.actionCreateKey),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: t.labelApiKeyName,
                  hintText: t.hintApiKeyName,
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: keyController,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
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

      final newKey = await AuthService.createApiKey(
        name: name,
        key: keyValue.isNotEmpty ? keyValue : null,
      );
      if (!mounted) return;
      setState(() {
        _apiKeys.insert(0, newKey);
      });
      NotifyUtils.showNotify(context, t.msgApiKeyCreated);
    } catch (e) {
      if (!mounted) return;
      NotifyUtils.showNotify(context, e.toString());
    } finally {
      nameController.dispose();
      keyController.dispose();
    }
  }

  Future<void> _deleteApiKey(Map<String, dynamic> key) async {
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
        _apiKeys.removeWhere((k) {
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

  Future<void> _showChangePasswordDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
  }

  Future<void> _copyApiKey(Map<String, dynamic> key) async {
    final t = AppLocalizations.of(context)!;
    final keyValue = key['key']?.toString() ??
        key['apiKey']?.toString() ??
        key['token']?.toString() ??
        '';
    if (keyValue.isNotEmpty) {
      final ok = await CopyHelper.copy(keyValue);
      if (mounted) {
        NotifyUtils.showNotify(
            context, ok ? t.msgApiKeyCopied : t.msgCopyFailed);
      }
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

  // --- UI Build Methods ---

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final dimIconColor = colorScheme.onSurfaceVariant.withAlpha(100);
    final dimTextColor = colorScheme.onSurfaceVariant.withAlpha(150);
    final dividerColor = colorScheme.outlineVariant.withAlpha(80);

    return Scaffold(
      body: _isLoading
          ? const Center(child: LoadingView(type: LoadingType.list))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _buildServerSection(t, colorScheme, textTheme, dimIconColor, dimTextColor, dividerColor),
                const SizedBox(height: 28),
                if (PlatformDetector.isWeb) ...[
                  _buildApiKeySection(t, colorScheme, textTheme, dimIconColor, dimTextColor, dividerColor),
                  const SizedBox(height: 28),
                ],
                _buildGeneralSection(t, colorScheme, textTheme, dividerColor),
              ],
            ),
    );
  }

  Widget _iconContainer(IconData icon, double size, Color bgColor, Color iconColor) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(size >= 40 ? 12 : 10),
      ),
      child: Icon(icon, size: size * 0.5, color: iconColor),
    );
  }

  Widget _buildSectionHeader(
    String title,
    IconData icon,
    ColorScheme colorScheme,
    TextTheme textTheme, {
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Row(
        children: [
          _iconContainer(icon, 34, colorScheme.primaryContainer, colorScheme.primary),
          const SizedBox(width: 12),
          Text(title, style: textTheme.titleMedium),
          const Spacer(),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String text,
    required Color dimIconColor,
    required Color dimTextColor,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: dimIconColor.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: dimIconColor),
          ),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: dimTextColor,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: dimTextColor.withAlpha(120),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: dimIconColor.withAlpha(10),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: content,
        ),
      );
    }

    return content;
  }

  // --- Server Section ---

  Widget _buildServerSection(
    AppLocalizations t,
    ColorScheme colorScheme,
    TextTheme textTheme,
    Color dimIconColor,
    Color dimTextColor,
    Color dividerColor,
  ) {
    final isWeb = PlatformDetector.isWeb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          t.sectionServers,
          RemixIcon.serverLine,
          colorScheme,
          textTheme,
          trailing: _buildAddButton(t.buttonAddServer, () => _showAddServerOptions(), colorScheme),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _servers.isEmpty
                ? _buildEmptyState(
                    icon: RemixIcon.addCircleLine,
                    text: t.buttonAddServer,
                    dimIconColor: colorScheme.primary,
                    dimTextColor: colorScheme.onSurface,
                    subtitle: t.hintAddServer,
                    onTap: () => _showAddServerOptions(),
                  )
                : Column(
                    children: List.generate(_servers.length, (index) {
                      return _buildServerItem(
                        t: t,
                        server: _servers[index],
                        index: index,
                        isWeb: isWeb,
                        colorScheme: colorScheme,
                        textTheme: textTheme,
                        dividerColor: dividerColor,
                      );
                    }),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddButton(String tooltip, VoidCallback onPressed, ColorScheme colorScheme) {
    return Material(
      color: colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          // 显式语义 label：纯图标按钮在语义树中无文本可定位，
          // Selenium 生产测试（列表非空时）依赖 aria-label 点击该按钮
          child: Semantics(
            label: tooltip,
            button: true,
            child: Icon(RemixIcon.addLine, size: 20, color: colorScheme.primary),
          ),
        ),
      ),
    );
  }

  Widget _buildServerItem({
    required AppLocalizations t,
    required Map<String, String> server,
    required int index,
    required bool isWeb,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required Color dividerColor,
  }) {
    final isActive = server['url'] == _activeApiUrl;
    final isWebBackend = isWeb &&
        _webBackendUrl != null &&
        _webBackendUrl!.isNotEmpty &&
        server['url'] == _webBackendUrl;
    final isLast = index == _servers.length - 1;
    final serverIconBg = isActive ? colorScheme.primary : colorScheme.surfaceContainerHighest;
    final serverIconColor = isActive ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            leading: _iconContainer(
              isActive ? RemixIcon.serverLine : RemixIcon.serverLine,
              42,
              serverIconBg,
              serverIconColor,
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    server['name'] ?? 'Unnamed',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      t.labelActive,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onPrimary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
                if (isWebBackend) ...[
                  const SizedBox(width: 6),
                  Icon(RemixIcon.lockLine, size: 14, color: colorScheme.onSurfaceVariant.withAlpha(150)),
                ],
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _maskUrl(server['url'] ?? ''),
                style: textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
            trailing: isWebBackend
                ? null
                : PopupMenuButton<String>(
                    icon: Icon(RemixIcon.more2Fill, size: 20, color: colorScheme.onSurfaceVariant),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showServerDialog(server: server, index: index);
                      } else if (value == 'copy') {
                        _copyServer(index);
                      } else if (value == 'delete') {
                        _deleteServer(index);
                      }
                    },
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            Icon(RemixIcon.editLine, size: 20, color: colorScheme.onSurface),
                            const SizedBox(width: 12),
                            Text(t.actionEdit),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'copy',
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            Icon(RemixIcon.fileCopyLine, size: 20, color: colorScheme.onSurface),
                            const SizedBox(width: 12),
                            Text(t.actionCopy),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            Icon(RemixIcon.deleteBinLine, size: 20, color: colorScheme.error),
                            const SizedBox(width: 12),
                            Text(t.actionDelete, style: TextStyle(color: colorScheme.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
            onTap: () {
              if (!isActive && !isWebBackend) {
                _switchServer(server);
              }
            },
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        if (!isLast) Divider(indent: 72, endIndent: 16, color: dividerColor),
      ],
    );
  }

  // --- API Key Section ---

  Widget _buildApiKeySection(
    AppLocalizations t,
    ColorScheme colorScheme,
    TextTheme textTheme,
    Color dimIconColor,
    Color dimTextColor,
    Color dividerColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          t.titleApiKeys,
          RemixIcon.key2Line,
          colorScheme,
          textTheme,
          trailing: _buildAddButton(t.actionCreateKey, _createApiKey, colorScheme),
        ),
        // 标注当前显示的 API Key 所属服务器，避免切换服务器后误以为仍是当前服务器的 key
        if (_webBackendUrl != null && _webBackendUrl!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              t.titleApiKeysFor(_webBackendUrl!),
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _buildApiKeyContent(t, colorScheme, textTheme, dimIconColor, dimTextColor, dividerColor),
          ),
        ),
      ],
    );
  }

  Widget _buildApiKeyContent(
    AppLocalizations t,
    ColorScheme colorScheme,
    TextTheme textTheme,
    Color dimIconColor,
    Color dimTextColor,
    Color dividerColor,
  ) {
    if (_isLoadingKeys) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_apiKeyError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Icon(RemixIcon.errorWarningLine, size: 36, color: colorScheme.error),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _apiKeyError!,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loadApiKeys,
              icon: const Icon(RemixIcon.refreshLine, size: 18),
              label: Text(t.msgRetry),
            ),
          ],
        ),
      );
    }

    if (_apiKeys.isEmpty) {
      return _buildEmptyState(
        icon: RemixIcon.key2Line,
        text: t.msgNoApiKeys,
        dimIconColor: dimIconColor,
        dimTextColor: dimTextColor,
      );
    }

    return Column(
      children: List.generate(_apiKeys.length, (index) {
        return _buildApiKeyItem(
          _apiKeys[index],
          index == _apiKeys.length - 1,
          t,
          colorScheme,
          textTheme,
          dividerColor,
        );
      }),
    );
  }

  Widget _buildApiKeyItem(
    Map<String, dynamic> key,
    bool isLast,
    AppLocalizations t,
    ColorScheme colorScheme,
    TextTheme textTheme,
    Color dividerColor,
  ) {
    final keyValue = key['key']?.toString() ??
        key['apiKey']?.toString() ??
        key['token']?.toString() ??
        '';
    final name = key['name']?.toString() ?? key['id']?.toString() ?? 'Key';
    final createdAt = _formatDate(key['created_at']?.toString());
    final expiresAt = key['expires_at']?.toString();
    final keyHash = '$name-$createdAt-${keyValue.length}'.hashCode;
    final isVisible = _visibleApiKeys.contains(keyHash);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _iconContainer(RemixIcon.key2Line, 36, colorScheme.tertiaryContainer, colorScheme.tertiary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        if (createdAt.isNotEmpty)
                          Text('${t.labelCreatedAt}: $createdAt', style: textTheme.bodySmall),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(isVisible ? RemixIcon.eyeOffLine : RemixIcon.eyeLine, size: 18),
                    onPressed: () {
                      setState(() {
                        if (isVisible) {
                          _visibleApiKeys.remove(keyHash);
                        } else {
                          _visibleApiKeys.add(keyHash);
                        }
                      });
                    },
                    tooltip: isVisible ? t.actionHide : t.actionShow,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(RemixIcon.fileCopyLine, size: 18),
                    onPressed: () => _copyApiKey(key),
                    tooltip: t.actionCopy,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: Icon(RemixIcon.deleteBinLine, size: 18, color: colorScheme.error),
                    onPressed: () => _deleteApiKey(key),
                    tooltip: t.actionDelete,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(RemixIcon.key2Line, size: 14, color: colorScheme.onSurfaceVariant.withAlpha(150)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isVisible ? keyValue : _maskApiKey(keyValue),
                        style: textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (expiresAt != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(RemixIcon.timeLine, size: 14, color: colorScheme.onSurfaceVariant.withAlpha(150)),
                    const SizedBox(width: 6),
                    Text('${t.labelExpiresAt}: ${_formatDate(expiresAt)}', style: textTheme.bodySmall),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (!isLast) Divider(indent: 64, endIndent: 16, color: dividerColor),
      ],
    );
  }

  // --- General Section ---

  Widget _buildGeneralSection(
    AppLocalizations t,
    ColorScheme colorScheme,
    TextTheme textTheme,
    Color dividerColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(t.sectionOther, RemixIcon.settings3Line, colorScheme, textTheme),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                _buildSettingDropdown(
                  icon: RemixIcon.globalLine,
                  title: t.labelLanguage,
                  value: _currentLanguage,
                  items: [
                    DropdownMenuItem(value: 'system', child: Text(t.optionSystem)),
                    DropdownMenuItem(value: 'en', child: Text(t.optionEnglish)),
                    DropdownMenuItem(value: 'zh', child: Text(t.optionChinese)),
                  ],
                  onChanged: _onLanguageChanged,
                  colorScheme: colorScheme,
                ),
                _buildSettingDivider(dividerColor),
                _buildSettingDropdown(
                  icon: RemixIcon.timeLine,
                  title: t.labelTimezone,
                  value: _currentTimezone,
                  items: [
                    DropdownMenuItem(value: 'system', child: Text(t.optionSystem)),
                    DropdownMenuItem(value: 'utc', child: Text(t.optionUtc)),
                    DropdownMenuItem(value: 'utc+8', child: Text(t.optionUtcPlus8)),
                    DropdownMenuItem(value: 'utc+9', child: Text(t.optionUtcPlus9)),
                    DropdownMenuItem(value: 'utc-5', child: Text(t.optionUtcMinus5)),
                    DropdownMenuItem(value: 'utc+1', child: Text(t.optionUtcPlus1)),
                  ],
                  onChanged: _updateTimezone,
                  colorScheme: colorScheme,
                ),
                _buildSettingDivider(dividerColor),
                _buildSettingTile(
                  icon: RemixIcon.archiveLine,
                  title: t.titleBackupRestore,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BackupScreen()),
                    );
                  },
                  colorScheme: colorScheme,
                  trailing: Icon(RemixIcon.arrowRightSLine, color: colorScheme.onSurfaceVariant),
                ),
                _buildSettingDivider(dividerColor),
                _buildSettingTile(
                  icon: RemixIcon.robotLine,
                  title: t.titleAiProviders,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AiProvidersScreen()),
                    );
                  },
                  colorScheme: colorScheme,
                  trailing: Icon(RemixIcon.arrowRightSLine, color: colorScheme.onSurfaceVariant),
                ),
                _buildSettingDivider(dividerColor),
                _buildSettingTile(
                  icon: RemixIcon.terminalBoxLine,
                  title: t.agentDebugTitle,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AgentDebugLogsScreen()),
                    );
                  },
                  colorScheme: colorScheme,
                  trailing: Icon(RemixIcon.arrowRightSLine, color: colorScheme.onSurfaceVariant),
                ),
                if (PlatformDetector.isWeb) ...[
                  _buildSettingDivider(dividerColor),
                  _buildSettingTile(
                    icon: RemixIcon.user3Line,
                    title: t.titleProfileSettings,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
                      );
                    },
                    colorScheme: colorScheme,
                    trailing: Icon(RemixIcon.arrowRightSLine, color: colorScheme.onSurfaceVariant),
                  ),
                  _buildSettingDivider(dividerColor),
                  _buildSettingTile(
                    icon: RemixIcon.mailSettingsLine,
                    title: t.titleSystemSettings,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const EmailSettingsScreen()),
                      );
                    },
                    colorScheme: colorScheme,
                    trailing: Icon(RemixIcon.arrowRightSLine, color: colorScheme.onSurfaceVariant),
                  ),
                ],
                if (!PlatformDetector.isWeb) ...[
                  _buildSettingDivider(dividerColor),
                  _buildSettingTile(
                    icon: RemixIcon.refreshLine,
                    title: t.actionUpdate,
                    onTap: _checkUpdate,
                    colorScheme: colorScheme,
                    trailing: Icon(RemixIcon.arrowRightSLine, color: colorScheme.onSurfaceVariant),
                  ),
                ],
                if (PlatformDetector.isWeb) ...[
                  _buildSettingDivider(dividerColor),
                  _buildSettingTile(
                    icon: RemixIcon.lockPasswordLine,
                    title: t.actionChangePassword,
                    onTap: _showChangePasswordDialog,
                    colorScheme: colorScheme,
                    trailing: Icon(RemixIcon.arrowRightSLine, color: colorScheme.onSurfaceVariant),
                  ),
                  _buildSettingDivider(dividerColor),
                  _buildSettingTile(
                    icon: RemixIcon.logoutBoxLine,
                    title: t.btnLogout,
                    onTap: () async {
                      await AuthService.logout();
                      if (mounted) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                        );
                      }
                    },
                    colorScheme: colorScheme,
                    trailing: Icon(RemixIcon.arrowRightSLine, color: colorScheme.onSurfaceVariant),
                  ),
                ],
                _buildSettingDivider(dividerColor),
                _buildSettingTile(
                  icon: RemixIcon.bookOpenLine,
                  title: t.labelApiDocs,
                  onTap: _openApiDocs,
                  colorScheme: colorScheme,
                  trailing: Icon(RemixIcon.externalLinkLine, size: 18, color: colorScheme.onSurfaceVariant),
                ),
                _buildSettingDivider(dividerColor),
                _buildSettingTile(
                  icon: RemixIcon.bookReadLine,
                  title: t.labelRedoc,
                  onTap: _openRedoc,
                  colorScheme: colorScheme,
                  trailing: Icon(RemixIcon.externalLinkLine, size: 18, color: colorScheme.onSurfaceVariant),
                ),
                _buildSettingDivider(dividerColor),
                _buildSettingTile(
                  icon: RemixIcon.terminalLine,
                  title: t.labelGithub,
                  onTap: _openGithub,
                  colorScheme: colorScheme,
                  trailing: Icon(RemixIcon.externalLinkLine, size: 18, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        if (_versionText.isNotEmpty) ...[
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'v$_versionText',
                style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
        // 构建时间（CI 注入 BUILD_TIME，本地构建为空时隐藏）
        if (widget.buildTime.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              '${t.labelBuildTime}：${widget.buildTime.trim()}',
              style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
        // 与底部悬浮导航栏同高的占位，避免版本号/构建时间被"概览、容器"等 tab 遮挡
        const BottomNavBarSpacer(),
      ],
    );
  }

  Widget _buildSettingDropdown({
    required IconData icon,
    required String title,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
    required ColorScheme colorScheme,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _iconContainer(icon, 36, colorScheme.surfaceContainerHighest, colorScheme.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(
            child: DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: title,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              initialValue: value,
              items: items,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    Widget? trailing,
  }) {
    return ListTile(
      leading: _iconContainer(icon, 36, colorScheme.surfaceContainerHighest, colorScheme.onSurfaceVariant),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      trailing: trailing,
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _buildSettingDivider(Color dividerColor) {
    return Divider(indent: 66, endIndent: 16, color: dividerColor);
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      await AuthService.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      NotifyUtils.showNotify(context, AppLocalizations.of(context)!.msgPasswordChanged);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        NotifyUtils.showNotify(context, e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(t.actionChangePassword),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPasswordField(
                controller: _currentPasswordController,
                label: t.labelCurrentPassword,
                obscureText: _obscureCurrentPassword,
                onVisibilityChanged: () => setState(() {
                  _obscureCurrentPassword = !_obscureCurrentPassword;
                }),
                textInputAction: TextInputAction.next,
                validator: (value) => value == null || value.isEmpty ? t.msgPasswordRequired : null,
              ),
              const SizedBox(height: 16),
              _buildPasswordField(
                controller: _newPasswordController,
                label: t.labelNewPassword,
                obscureText: _obscureNewPassword,
                onVisibilityChanged: () => setState(() {
                  _obscureNewPassword = !_obscureNewPassword;
                }),
                textInputAction: TextInputAction.next,
                validator: (value) => value == null || value.isEmpty ? t.msgPasswordRequired : null,
              ),
              const SizedBox(height: 16),
              _buildPasswordField(
                controller: _confirmPasswordController,
                label: t.labelConfirmNewPassword,
                obscureText: _obscureConfirmPassword,
                onVisibilityChanged: () => setState(() {
                  _obscureConfirmPassword = !_obscureConfirmPassword;
                }),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: (value) {
                  if (value == null || value.isEmpty) return t.msgPasswordRequired;
                  return value == _newPasswordController.text ? null : t.msgPasswordMismatch;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: Text(t.actionCancel),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(t.actionChangePassword),
        ),
      ],
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool obscureText,
    required VoidCallback onVisibilityChanged,
    required TextInputAction textInputAction,
    required String? Function(String?) validator,
    ValueChanged<String>? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      enabled: !_isSubmitting,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(RemixIcon.lockPasswordLine),
        suffixIcon: IconButton(
          icon: Icon(obscureText ? RemixIcon.eyeOffLine : RemixIcon.eyeLine),
          onPressed: onVisibilityChanged,
        ),
      ),
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
    );
  }
}
