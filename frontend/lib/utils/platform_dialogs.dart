import 'package:flutter/material.dart';
import 'platform_detector.dart';

/// 按平台分发弹窗：
/// 手机端（Android/iOS/ohos）使用 showModalBottomSheet 弹出底部操作菜单；
/// 其他端（Web、桌面等）使用 showDialog + AlertDialog 弹出居中对话框。
class PlatformDialogs {
  static bool get _isMobile =>
      PlatformDetector.isAndroid ||
      PlatformDetector.isIOS ||
      PlatformDetector.isOhos;

  /// 展示操作菜单内容 [content]。
  /// [backgroundColor]、[isScrollControlled] 仅手机端底部面板生效，
  /// 用于保持手机端原有视觉不变。
  static void showActionMenu({
    required BuildContext context,
    required Widget content,
    Color? backgroundColor,
    bool isScrollControlled = false,
  }) {
    if (_isMobile) {
      showModalBottomSheet(
        context: context,
        backgroundColor: backgroundColor,
        isScrollControlled: isScrollControlled,
        builder: (_) => content,
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(content: content),
      );
    }
  }
}
