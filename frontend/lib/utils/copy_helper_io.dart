import 'package:flutter/services.dart';

/// 非 Web 平台复制辅助：沿用系统剪贴板（移动端 / 桌面 / 鸿蒙）。
class CopyHelper {
  static Future<bool> copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  }
}
