import 'package:flutter/material.dart';
import '../theme/theme_extensions.dart';

class StatusBadge extends StatelessWidget {
  final String status;
  final double fontSize;

  const StatusBadge({super.key, required this.status, this.fontSize = 12});

  static Color colorFor(String status, ThemeData theme) {
    final dockerColors = theme.extension<DockerColors>();
    switch (status.toLowerCase()) {
      case 'running':
        return dockerColors?.statusRunning ?? Colors.green;
      case 'exited':
        return dockerColors?.statusExited ?? Colors.red;
      case 'created':
        return dockerColors?.statusCreated ?? Colors.blue;
      case 'restarting':
        return dockerColors?.statusRestarting ?? Colors.orange;
      case 'paused':
        return dockerColors?.statusPaused ?? Colors.amber;
      default:
        return Colors.grey;
    }
  }

  Color _getColor(BuildContext context) {
    return colorFor(status, Theme.of(context));
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: 0.1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            status,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
