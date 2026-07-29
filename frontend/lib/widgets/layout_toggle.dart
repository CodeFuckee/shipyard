import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';

class LayoutToggle extends StatelessWidget {
  final bool isCompactMode;
  final VoidCallback onToggle;

  const LayoutToggle({
    super.key,
    required this.isCompactMode,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Icon(
            isCompactMode ? RemixIcon.layoutGridLine : RemixIcon.listView,
            size: 22,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
