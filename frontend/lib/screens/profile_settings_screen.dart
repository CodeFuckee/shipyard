import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/utils/notify_utils.dart';
import '../services/auth_service.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isSendingTest = false;
  String? _loadError;
  String? _username;
  String? _boundEmail;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await AuthService.getProfile();
      if (!mounted) return;

      setState(() {
        _username = profile['username']?.toString() ?? '';
        _boundEmail = profile['email']?.toString();
        _emailController.text = _boundEmail ?? '';
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

  Future<void> _sendTestEmail() async {
    if (_isSendingTest) return;

    final email = _boundEmail;
    if (email == null || email.isEmpty) {
      if (mounted) {
        NotifyUtils.showNotify(
          context,
          AppLocalizations.of(context)!.msgNoEmailBound,
        );
      }
      return;
    }

    setState(() => _isSendingTest = true);
    try {
      await AuthService.sendTestEmail(toEmail: email);
      if (!mounted) return;
      NotifyUtils.showNotify(
        context,
        AppLocalizations.of(context)!.msgTestEmailSent,
      );
    } catch (e) {
      if (mounted) {
        NotifyUtils.showNotify(context, e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isSendingTest = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() => _isSubmitting = true);
    try {
      final email = _emailController.text.trim();
      final result = await AuthService.updateProfile(email: email);
      if (!mounted) return;

      final t = AppLocalizations.of(context)!;
      final wasBound = _boundEmail != null && _boundEmail!.isNotEmpty;
      _boundEmail = result['email']?.toString() ?? email;
      _emailController.text = _boundEmail!;

      NotifyUtils.showNotify(
        context,
        wasBound ? t.msgEmailUpdated : t.msgEmailBound,
      );
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
        title: Text(t.titleProfileSettings),
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
                  _loadProfile();
                },
                icon: const Icon(RemixIcon.refreshLine),
                label: Text(t.msgRetry),
              ),
            ],
          ),
        ),
      );
    }

    final hasEmail = _boundEmail != null && _boundEmail!.isNotEmpty;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 用户头像/图标区域
          Center(
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    RemixIcon.user3Line,
                    size: 40,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _username ?? '',
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  hasEmail ? _boundEmail! : t.labelNotBound,
                  style: textTheme.bodyMedium?.copyWith(
                    color: hasEmail ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // 邮箱绑定区域
          _buildSectionHeader(t.labelEmail, RemixIcon.mailLine, colorScheme, textTheme),
          const SizedBox(height: 8),
          TextFormField(
            controller: _emailController,
            enabled: !_isSubmitting,
            decoration: InputDecoration(
              labelText: t.labelEmail,
              hintText: t.hintEmail,
              prefixIcon: const Icon(RemixIcon.mailLine),
            ),
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return t.msgEmailRequired;
              }
              final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
              if (!emailRegex.hasMatch(value.trim())) {
                return t.msgEmailInvalid;
              }
              return null;
            },
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              t.hintEmailBind,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          // 发送测试邮件按钮（仅在已绑定邮箱时显示）
          if (hasEmail) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _isSendingTest ? null : _sendTestEmail,
                icon: _isSendingTest
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(RemixIcon.mailSendLine),
                label: Text(
                  _isSendingTest ? t.msgSendingTestEmail : t.actionSendTestEmail,
                ),
              ),
            ),
          ],

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
              label: Text(
                _isSubmitting
                    ? t.msgConnecting
                    : (hasEmail ? t.actionChangeEmail : t.actionBindEmail),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    IconData icon,
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
            icon,
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
