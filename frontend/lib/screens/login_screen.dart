import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/oidc_service.dart';
import 'main_tab_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  bool _obscurePassword = true;
  bool _oidcAvailable = false;
  String? _oidcServerUrl;

  @override
  void initState() {
    super.initState();
    _loadOidcAvailability();
  }

  Future<void> _loadOidcAvailability() async {
    final serverUrl = kIsWeb ? _serverUrl : await OidcService.savedServerUrl();
    if (serverUrl == null || serverUrl.isEmpty) return;
    try {
      final url = await OidcService.buildAuthorizeUrl(serverUrl);
      if (!mounted) return;
      setState(() {
        _oidcServerUrl = serverUrl;
        _oidcAvailable = url.isNotEmpty;
      });
    } catch (_) {
      // 未配置或暂时不可达时继续显示本地管理员登录。
    }
  }

  String get _serverUrl {
    if (kDebugMode) {
      return 'http://localhost:8000';
    }
    return Uri.base.origin;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loginWithOidc() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final serverUrl = _oidcServerUrl ?? _serverUrl;
      final url = await OidcService.buildAuthorizeUrl(serverUrl);
      final redirected = await OidcService.redirectTo(url);
      if (!redirected && mounted) {
        setState(() => _error = '无法打开统一身份认证页面');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '无法启动统一身份认证：$error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _configureOidcServer() async {
    final controller = TextEditingController(
      text: _oidcServerUrl ?? 'https://',
    );
    final serverUrl = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('统一身份认证服务器'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Shipyard 服务器地址',
            hintText: 'https://shipyard.example.com',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('保存并检测'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (serverUrl == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await OidcService.saveServerUrl(serverUrl);
      await _loadOidcAvailability();
      if (mounted && !_oidcAvailable) {
        setState(() => _error = '服务器未启用统一身份认证或暂时不可达');
      }
    } on OidcException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await AuthService.login(
      serverUrl: _serverUrl,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      ignoreSsl: false,
    );

    if (!mounted) return;

    if (result.success) {
      // 通知密码管理器保存本次登录凭据,下次可直接自动填充
      TextInput.finishAutofillContext(shouldSave: true);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainTabScreen()),
      );
    } else {
      // 登录失败,通知密码管理器不保存当前输入
      TextInput.finishAutofillContext(shouldSave: false);
      setState(() {
        _isLoading = false;
        _error = result.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      RemixIcon.serverLine,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Docker Monitor',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 24),
                    Semantics(
                      textField: true,
                      label: t.labelUsername,
                      child: TextFormField(
                        controller: _usernameController,
                        // 注意:不要使用 autofillHints。ohos 定制版 Flutter 引擎
                        // 的 autofill form 管理有 bug(updateConfig 会重建并拆散
                        // 多字段 form,触发 Uncaught Error),Web 端改为在
                        // web/index.html 中手动注入 autocomplete 属性,详见
                        // web/index.html 的 flt-autofill-hints 脚本注释。
                        decoration: InputDecoration(
                          labelText: t.labelUsername,
                          hintText: t.hintUsername,
                          prefixIcon: const Icon(RemixIcon.userLine),
                          border: const OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                        autofocus: true,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return t.hintUsername;
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      textField: true,
                      label: t.labelPassword,
                      child: TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        // 同用户名框:不使用 autofillHints,Web 端由
                        // index.html 注入 autocomplete 属性
                        decoration: InputDecoration(
                          labelText: t.labelPassword,
                          hintText: t.hintPassword,
                          prefixIcon: const Icon(RemixIcon.lockLine),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? RemixIcon.eyeOffLine
                                  : RemixIcon.eyeLine,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _login(),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return t.hintPassword;
                          }
                          return null;
                        },
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        label: _error,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                RemixIcon.errorWarningLine,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onErrorContainer,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_oidcAvailable) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _loginWithOidc,
                          icon: const Icon(RemixIcon.shieldUserLine),
                          label: const Text('通过统一身份认证登录'),
                        ),
                      ),
                    ] else if (!kIsWeb) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _configureOidcServer,
                          icon: const Icon(RemixIcon.settings3Line),
                          label: const Text('配置统一身份认证服务器'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Semantics(
                      button: true,
                      label: t.btnLogin,
                      enabled: !_isLoading,
                      child: SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _login,
                          child: _isLoading
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFFFFFFF),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(t.msgConnecting),
                                  ],
                                )
                              : Text(t.btnLogin),
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
    );
  }
}
