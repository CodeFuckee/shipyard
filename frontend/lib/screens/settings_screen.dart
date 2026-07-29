import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:flutter/services.dart';
import 'package:mobile_portainer_flutter_module/screens/qr_scan_screen.dart';
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
import '../services/harmonyos_platform.dart';
import '../services/harmonyos_shared_prefs.dart';
import '../utils/platform_detector.dart';
import '../widgets/loading_view.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onSaved;
  const SettingsScreen({super.key, this.onSaved});

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
    final serverListJson = await prefs.getString('server_list');

    String? apiKey;
    if (serverListJson == null && activeApiUrl != null && activeApiUrl.isNotEmpty) {
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

      if (serverListJson != null) {
        try {
          final List<dynamic> decoded = jsonDecode(serverListJson);
          _servers = decoded.map((e) => Map<String, String>.from(e)).toList();
        } catch (e) {
          debugPrint('Error parsing server list: $e');
          _servers = [];
        }
      }

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
      await _saveServerList(prefs);
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

  Future<void> _saveServerList(dynamic prefs) async {
    await prefs.setString('server_list', jsonEncode(_servers));
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

  Future<void> _copyServer(int index) async {
    final t = AppLocalizations.of(context)!;
    final server = _servers[index];

    final newServer = Map<String, String>.from(server);
    newServer['name'] = '${server['name']} - Copy';

    setState(() {
      _servers.add(newServer);
    });

    final prefs = await _getPrefs();
    await _saveServerList(prefs);

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
    await _saveServerList(prefs);

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
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
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
                  _showServerDialog();
                },
              ),
            ],
          ),
        );
      },
    );
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

                  final prefs = await _getPrefs();
                  await _saveServerList(prefs);

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

  void _copyApiKey(Map<String, dynamic> key) {
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
          child: Icon(RemixIcon.addLine, size: 20, color: colorScheme.primary),
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
