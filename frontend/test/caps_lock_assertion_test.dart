import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 复现 Flutter 框架 bug：macOS Caps Lock synthesized KeyUpEvent
/// 在 _pressedKeys 中没有对应 KeyDownEvent 记录时触发 assertion。
///
/// 错误栈：
///   HardwareKeyboard._assertEventIsRegular (hardware_keyboard.dart:522)
///   HardwareKeyboard.handleKeyEvent (hardware_keyboard.dart:660)
///   KeyEventManager.handleKeyData (hardware_keyboard.dart:1103)
void main() {
  testWidgets('Caps Lock KeyUp without KeyDown triggers _pressedKeys assertion',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pump();

    // 只发送 KeyUpEvent，不发送 KeyDownEvent
    // 模拟 macOS 发送 synthesized Caps Lock KeyUp 的场景
    AssertionError? captured;

    try {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.capsLock);
      await tester.pump();
    } on AssertionError catch (e) {
      captured = e;
    }

    // 验证 assertion 被触发
    expect(captured, isNotNull,
        reason: 'Expected _pressedKeys assertion to fire for Caps Lock KeyUp');
    expect(
      captured!.toString(),
      contains('_pressedKeys.containsKey'),
    );
  });

  testWidgets('Caps Lock full down+up cycle works normally', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pump();

    bool handlerCalled = false;
    HardwareKeyboard.instance.addHandler((event) {
      handlerCalled = true;
      return false;
    });

    // 正常流程：先 down 再 up — 不应触发 assertion
    await tester.sendKeyDownEvent(LogicalKeyboardKey.capsLock);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.capsLock);
    await tester.pump();

    expect(handlerCalled, isTrue);
  });
}
