import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/utils/notify_utils.dart';
import '../services/auth_service.dart';

class EmailSettingsScreen extends StatefulWidget {
  const EmailSettingsScreen({super.key});

  @override
  State<EmailSettingsScreen> createState() => _EmailSettingsScreenState();
}

class _EmailSettingsScreenState extends State<EmailSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _loadError;

  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fromEmailController = TextEditingController();
  final _fromNameController = TextEditingController();
  final _timeoutController = TextEditingController();

  bool _useSsl = false;
  bool _useStarttls = true;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _fromEmailController.dispose();
    _fromNameController.dispose();
    _timeoutController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final config = await AuthService.getEmailConfig();
      if (!mounted) return;

      setState(() {
        _hostController.text = config['host']?.toString() ?? '';
        _portController.text = config['port']?.toString() ?? '';
        _usernameController.text = config['username']?.toString() ?? '';
        // 密码不回显，保留空让用户按需输入
        _passwordController.text = '';
        _fromEmailController.text = config['from_email']?.toString() ?? '';
        _fromNameController.text = config['from_name']?.toString() ?? '';
        _timeoutController.text = config['timeout']?.toString() ?? '10';
        _useSsl = config['use_ssl'] == true;
        _useStarttls = config['use_starttls'] == true;
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

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    // 先取消所有输入框焦点，避免 Web 端焦点冲突
    FocusScope.of(context).unfocus();

    setState(() => _isSubmitting = true);
    try {
      await AuthService.saveSmtpConfig(
        host: _hostController.text.trim(),
        port: int.parse(_portController.text.trim()),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        fromEmail: _fromEmailController.text.trim(),
        fromName: _fromNameController.text.trim().isEmpty
            ? 'Mobile Portainer'
            : _fromNameController.text.trim(),
        useSsl: _useSsl,
        useStarttls: _useStarttls,
        timeout: int.parse(_timeoutController.text.trim()),
      );
      if (!mounted) return;
      NotifyUtils.showNotify(context, AppLocalizations.of(context)!.msgSmtpSaved);
      // 返回前再次确保焦点已清除
      FocusScope.of(context).unfocus();
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.titleEmailSettings),
      ),
      body: _buildBody(t, colorScheme, textTheme),
    );
  }

  Widget _buildBody(AppLocalizations t, ColorScheme colorScheme, TextTheme textTheme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(RemixIcon.errorWarningLine, size: 48, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _loadError = null;
                  });
                  _loadConfig();
                },
                icon: const Icon(RemixIcon.refreshLine),
                label: Text(t.msgRetry),
              ),
            ],
          ),
        ),
      );
    }

    return Form(
      key: _formKey,
      child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionHeader(t.labelSmtpHost, colorScheme, textTheme),
            const SizedBox(height: 8),
            TextFormField(
              controller: _hostController,
              enabled: !_isSubmitting,
              decoration: InputDecoration(
                labelText: t.labelSmtpHost,
                hintText: t.hintSmtpHost,
                prefixIcon: const Icon(RemixIcon.serverLine),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '${t.labelSmtpHost} ${t.msgPasswordRequired}';
                }
                return null;
              },
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _portController,
              enabled: !_isSubmitting,
              decoration: InputDecoration(
                labelText: t.labelSmtpPort,
                hintText: t.hintSmtpPort,
                prefixIcon: const Icon(RemixIcon.linkM),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '${t.labelSmtpPort} ${t.msgPasswordRequired}';
                }
                final port = int.tryParse(value.trim());
                if (port == null || port < 1 || port > 65535) {
                  return t.hintSmtpPort;
                }
                return null;
              },
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 24),
            _buildSectionHeader(t.labelSmtpUsername, colorScheme, textTheme),
            const SizedBox(height: 8),
            TextFormField(
              controller: _usernameController,
              enabled: !_isSubmitting,
              decoration: InputDecoration(
                labelText: t.labelSmtpUsername,
                hintText: t.hintSmtpUsername,
                prefixIcon: const Icon(RemixIcon.userLine),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              enabled: !_isSubmitting,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: t.labelSmtpPassword,
                hintText: t.hintSmtpPasswordKeep,
                prefixIcon: const Icon(RemixIcon.lockPasswordLine),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? RemixIcon.eyeOffLine : RemixIcon.eyeLine,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 24),
            _buildSectionHeader(t.labelSmtpFromEmail, colorScheme, textTheme),
            const SizedBox(height: 8),
            TextFormField(
              controller: _fromEmailController,
              enabled: !_isSubmitting,
              decoration: InputDecoration(
                labelText: t.labelSmtpFromEmail,
                hintText: t.hintSmtpFromEmail,
                prefixIcon: const Icon(RemixIcon.mailLine),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '${t.labelSmtpFromEmail} ${t.msgPasswordRequired}';
                }
                return null;
              },
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _fromNameController,
              enabled: !_isSubmitting,
              decoration: InputDecoration(
                labelText: t.labelSmtpFromName,
                hintText: t.hintSmtpFromName,
                prefixIcon: const Icon(RemixIcon.userVoiceLine),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 24),
            _buildSectionHeader(t.labelSmtpTimeout, colorScheme, textTheme),
            const SizedBox(height: 8),
            TextFormField(
              controller: _timeoutController,
              enabled: !_isSubmitting,
              decoration: InputDecoration(
                labelText: t.labelSmtpTimeout,
                prefixIcon: const Icon(RemixIcon.timeLine),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '${t.labelSmtpTimeout} ${t.msgPasswordRequired}';
                }
                final timeout = int.tryParse(value.trim());
                if (timeout == null || timeout < 1 || timeout > 120) {
                  return '1-120 秒';
                }
                return null;
              },
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: Text(t.labelSmtpUseSsl),
                      value: _useSsl,
                      onChanged: _isSubmitting
                          ? null
                          : (value) {
                              setState(() {
                                _useSsl = value;
                                if (value) {
                                  _useStarttls = false;
                                }
                              });
                            },
                    ),
                    SwitchListTile(
                      title: Text(t.labelSmtpUseStarttls),
                      value: _useStarttls,
                      onChanged: _isSubmitting
                          ? null
                          : (value) {
                              setState(() {
                                _useStarttls = value;
                                if (value) {
                                  _useSsl = false;
                                }
                              });
                            },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(RemixIcon.checkLine),
                label: Text(_isSubmitting ? t.msgConnecting : t.buttonSave),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
  }

  Widget _buildSectionHeader(
    String title,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            RemixIcon.mailSettingsLine,
            size: 16,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
