import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Stack 中统一定位的 FloatingActionButton。
///
/// 默认位置与容器页面（main_tab_screen）保持一致：右下角、
/// `bottom: AppTheme.fabBottomInset`（避开底部导航栏）。
/// 当宿主 Stack 所在 Scaffold 已通过 bottomNavigationBar 避让导航栏时
/// （body 底部即导航栏顶部），应传 `bottom` 减去导航栏高度，
/// 保持 FAB 距屏幕底部的视觉位置不变。
/// 所有在 Stack 中手动定位的 FAB 都应使用本组件，避免位置不一致。
class StackFab extends StatelessWidget {
  const StackFab({
    super.key,
    required this.heroTag,
    required this.onPressed,
    required this.icon,
    this.bottom,
  });

  /// 唯一 Hero tag，避免同路由多个 FAB 冲突
  final String heroTag;

  final VoidCallback onPressed;

  final IconData icon;

  /// 距 Stack 底部的偏移。默认 `AppTheme.fabBottomInset`。
  final double? bottom;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: bottom ?? AppTheme.fabBottomInset,
      child: FloatingActionButton(
        heroTag: heroTag,
        onPressed: onPressed,
        child: Icon(icon),
      ),
    );
  }
}
