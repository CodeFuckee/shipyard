import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';

class ActionItem {
  final String label;
  final IconData icon;
  final Color color;
  final String actionCode;

  const ActionItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.actionCode,
  });
}

class ActionSheet {
  static void show({
    required BuildContext context,
    required Widget header,
    required List<ActionItem> actions,
    required void Function(String actionCode) onAction,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final colorScheme = Theme.of(context).colorScheme;
        return Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              header,
              const Divider(),
              ...actions.map(
                (action) => _ActionTile(
                  action: action,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onAction(action.actionCode);
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  static Widget buildActionButton({
    required BuildContext context,
    required ActionItem action,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: action.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: action.color.withValues(alpha: 0.15),
              ),
            ),
            child: Icon(action.icon, color: action.color, size: 24),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          action.label,
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final ActionItem action;
  final VoidCallback onTap;

  const _ActionTile({required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: action.color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: action.color.withValues(alpha: 0.15),
          ),
        ),
        child: Icon(action.icon, color: action.color, size: 20),
      ),
      title: Text(
        action.label,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Icon(
        RemixIcon.arrowRightSLine,
        color: colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}
