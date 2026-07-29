import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';

import '../theme/theme_extensions.dart';

enum ToastType { success, error, warning, info }

class _ToastSlot {
  OverlayEntry? entry;
}

class AppToast {
  static final Map<ToastType, OverlayEntry> _byType = {};
  static final List<_ToastSlot> _slots =
      List.generate(3, (_) => _ToastSlot());

  static void show(BuildContext context, String message, ToastType type) {
    // Remove any existing toast of the same type, but guard against
    // entries whose _overlay has been detached (e.g. displaced by slot
    // reclamation).  The `.mounted` check alone isn't always enough in
    // test/synthetic environments.
    final existing = _byType[type];
    if (existing != null && existing.mounted) {
      try {
        existing.remove();
      } catch (_) {
        // entry was already detached — just clear the stale references.
      }
      for (final slot in _slots) {
        if (slot.entry == existing) slot.entry = null;
      }
    }
    _byType.remove(type);

    _ToastSlot? slot;
    for (final s in _slots) {
      if (s.entry == null || !s.entry!.mounted) {
        // Only call remove() if the entry is actually mounted;
        // otherwise clear the stale reference.
        if (s.entry?.mounted == true) {
          s.entry!.remove();
        }
        s.entry = null;
        slot = s;
        break;
      }
    }
    slot ??= _slots.first;
    // Defensive: only remove if still mounted, then clear the slot.
    if (slot.entry?.mounted == true) {
      slot.entry!.remove();
    }
    slot.entry = null;
    final targetSlot = slot;

    final overlay = Overlay.of(context);
    final topPadding = MediaQuery.of(context).padding.top;
    final slotIndex = _slots.indexOf(targetSlot);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: topPadding + 8 + slotIndex * 64.0,
        left: 0,
        right: 0,
        child: Center(
          child: _ToastWidget(
            message: message,
            type: type,
            onDismiss: () {
              entry.remove();
              if (_byType[type] == entry) _byType.remove(type);
              if (targetSlot.entry == entry) targetSlot.entry = null;
            },
          ),
        ),
      ),
    );

    overlay.insert(entry);
    _byType[type] = entry;
    targetSlot.entry = entry;
  }

  static void success(BuildContext context, String message) =>
      show(context, message, ToastType.success);
  static void error(BuildContext context, String message) =>
      show(context, message, ToastType.error);
  static void warning(BuildContext context, String message) =>
      show(context, message, ToastType.warning);
  static void info(BuildContext context, String message) =>
      show(context, message, ToastType.info);
}

/// Theme-aware color resolver for each toast type.
///
/// Colors are derived from the app's [ColorScheme] and [DockerColors]
/// extension so they automatically adapt to light / dark mode and stay
/// consistent with the Arco Design palette used throughout the app.
class _ToastAppearance {
  final Color border;
  final Color background;
  final IconData icon;

  const _ToastAppearance({
    required this.border,
    required this.background,
    required this.icon,
  });

  /// Arco Design functional green — same value as [DockerColors.statusRunning].
  static const _successGreen = Color(0xFF00B42A);
  static const _successGreenDark = Color(0xFF52CC6D);

  static _ToastAppearance of(ColorScheme cs, DockerColors? dc, ToastType type) {
    final isDark = cs.brightness == Brightness.dark;
    switch (type) {
      case ToastType.success:
        // Arco Design success green — prefer DockerColors extension when
        // available, otherwise fall back to the hard-coded Arco green value.
        final green = dc?.statusRunning ??
            (isDark ? _successGreenDark : _successGreen);
        return _ToastAppearance(
          border: green,
          background: green.withAlpha(isDark ? 25 : 18),
          icon: RemixIcon.checkboxCircleFill,
        );
      case ToastType.error:
        return _ToastAppearance(
          border: cs.error,
          background: cs.error.withAlpha(isDark ? 30 : 18),
          icon: RemixIcon.errorWarningFill,
        );
      case ToastType.warning:
        return _ToastAppearance(
          border: cs.tertiary,
          background: cs.tertiary.withAlpha(isDark ? 30 : 20),
          icon: RemixIcon.alertFill,
        );
      case ToastType.info:
        return _ToastAppearance(
          border: cs.primary,
          background: cs.primary.withAlpha(isDark ? 25 : 18),
          icon: RemixIcon.informationFill,
        );
    }
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final ToastType type;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.type,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _dismissTimer;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.6, curve: Curves.easeOut),
      ),
    );

    _controller.forward();
    _dismissTimer = Timer(const Duration(milliseconds: 3000), _dismiss);
  }

  void _dismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    _dismissTimer?.cancel();
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dc = theme.extension<DockerColors>();
    final appearance = _ToastAppearance.of(cs, dc, widget.type);
    final isDark = cs.brightness == Brightness.dark;

    // Frosted-glass base — surface container with the accent tint overlaid.
    final baseBg = Color.alphaBlend(
      appearance.background,
      cs.surfaceContainerLowest,
    );

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity != null &&
                details.primaryVelocity! < -100) {
              _dismiss();
            }
          },
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width - 32,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                        cs.surfaceContainerLowest.withAlpha(isDark ? 180 : 160),
                        baseBg,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: cs.outlineVariant.withAlpha(isDark ? 80 : 120),
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: cs.shadow.withAlpha(isDark ? 60 : 25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                          spreadRadius: -2,
                        ),
                      ],
                    ),
                    child: IntrinsicWidth(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Left accent stripe + icon
                          Container(
                            width: 3,
                            height: 24,
                            decoration: BoxDecoration(
                              color: appearance.border,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(appearance.icon,
                              color: appearance.border, size: 20),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              widget.message,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurface,
                                fontSize: 13.5,
                                height: 1.35,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _dismiss,
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                RemixIcon.closeFill,
                                color: cs.onSurfaceVariant
                                    .withAlpha(isDark ? 120 : 80),
                                size: 16,
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
          ),
        ),
      ),
    );
  }
}
