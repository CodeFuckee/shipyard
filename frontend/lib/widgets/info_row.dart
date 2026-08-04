import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import '../l10n/app_localizations.dart';
import '../theme/theme_extensions.dart';
import '../utils/copy_helper.dart';

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool showCopyButton;
  final String? copyValue;
  final bool isError;
  final VoidCallback? onTap;
  final bool isMonospace;
  final double labelWidth;

  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.showCopyButton = false,
    this.copyValue,
    this.isError = false,
    this.onTap,
    this.isMonospace = false,
    this.labelWidth = 100,
  });

  /// 复制值并提示结果。先获取 messenger / 本地化引用再 await，
  /// 避免 await 期间组件被卸载导致 context 失效。
  Future<void> _copyValue(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final t = AppLocalizations.of(context)!;
    final ok = await CopyHelper.copy(copyValue ?? value);
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? 'Copied' : t.msgCopyFailed),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dockerColors = Theme.of(context).extension<DockerColors>();
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final labelStyle = textTheme.bodySmall?.copyWith(
      color: dockerColors?.labelText ?? Colors.grey,
      fontWeight: FontWeight.w500,
    );

    final valueStyle = (textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: isError
          ? (dockerColors?.statusExited ?? Colors.red)
          : (dockerColors?.valueText ?? colorScheme.onSurface),
      fontFamily: isMonospace ? 'monospace' : null,
      decoration: onTap != null ? TextDecoration.underline : null,
      decorationColor: colorScheme.primary,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(label, style: labelStyle),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              onLongPress: () {
                _copyValue(context);
              },
              child: Text(value, style: valueStyle),
            ),
          ),
          if (showCopyButton)
            InkWell(
              onTap: () {
                _copyValue(context);
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  RemixIcon.fileCopyLine,
                  size: 16,
                  color: dockerColors?.copyButton ?? Colors.grey,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
