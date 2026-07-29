import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import '../theme/theme_extensions.dart';

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
                Clipboard.setData(ClipboardData(text: copyValue ?? value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              child: Text(value, style: valueStyle),
            ),
          ),
          if (showCopyButton)
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: copyValue ?? value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied'),
                    duration: Duration(seconds: 1),
                  ),
                );
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
