import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 与底部悬浮导航栏同高的空白占位组件。
///
/// 置于滚动内容末尾（如 ListView children 最后一项），使内容可以完全
/// 滚出悬浮导航栏（"概览、容器"等 tab）的覆盖区域，不被遮挡。
/// 高度 = 系统安全区 + 导航栏主体高度。
class BottomNavBarSpacer extends StatelessWidget {
  const BottomNavBarSpacer({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: AppTheme.bottomNavBarInset(context));
  }
}
