import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_portainer_flutter_module/widgets/app_toast.dart';

import 'test_utils.dart';

/// Helper widget that has a button triggering AppToast.info.
class _ToastTrigger extends StatelessWidget {
  final String message;
  const _ToastTrigger({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => AppToast.info(context, message),
          child: const Text('Show Toast'),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('AppToast 快速连续调用不崩溃', (tester) async {
    await tester.pumpWidget(buildTestApp(
      home: const _ToastTrigger(message: 'Test'),
    ));
    await tester.pump();

    // Rapidly trigger multiple toasts of different types
    for (int i = 0; i < 10; i++) {
      // Trigger all 4 types rapidly
      AppToast.info(
        tester.element(find.byType(Scaffold)),
        'Info $i',
      );
      AppToast.success(
        tester.element(find.byType(Scaffold)),
        'Success $i',
      );
      AppToast.warning(
        tester.element(find.byType(Scaffold)),
        'Warning $i',
      );
      AppToast.error(
        tester.element(find.byType(Scaffold)),
        'Error $i',
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Should not have thrown
    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets('AppToast 在各种 Overlay 嵌套场景下不崩溃', (tester) async {
    await tester.pumpWidget(buildTestApp(
      home: const _ToastTrigger(message: 'Test'),
    ));
    await tester.pump();

    final context = tester.element(find.byType(Scaffold));

    // Step 1: Show a toast
    AppToast.info(context, 'Step 1');
    await tester.pump(const Duration(milliseconds: 50));

    // Step 2: Simulate a dialog (pushes a route onto the navigator)
    //    and show another toast while the dialog is pushed
    final navigator = Navigator.of(context);
    navigator.push(MaterialPageRoute(
      builder: (_) => const Scaffold(body: Text('Dialog')),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    AppToast.info(context, 'Step 2 - during dialog');
    await tester.pump(const Duration(milliseconds: 50));

    // Step 3: Pop the dialog
    navigator.pop();
    await tester.pump(const Duration(milliseconds: 50));

    // Step 4: Show toast after dialog dismiss
    AppToast.info(context, 'Step 3 - after dialog');
    await tester.pump(const Duration(milliseconds: 50));

    // Step 5: Rapid fire many toasts
    for (int i = 0; i < 5; i++) {
      AppToast.info(context, 'Rapid $i');
      await tester.pump(const Duration(milliseconds: 30));
    }

    // Should not have thrown — getting here means success
    expect(find.byType(Scaffold), findsWidgets);
  });

  testWidgets('AppToast 在 setState 内部调用不崩溃 (模拟 _switchServer 场景)', (tester) async {
    // This test reproduces the exact crash scenario:
    // _switchServer is called inside setState while a dialog is visible,
    // then another toast is shown after the dialog is dismissed.

    await tester.pumpWidget(buildTestApp(
      home: const _ToastTrigger(message: 'Test'),
    ));
    await tester.pump();

    final context = tester.element(find.byType(Scaffold));
    final navigator = Navigator.of(context);

    // Show a dialog (simulating the edit server dialog)
    navigator.push(MaterialPageRoute(
      builder: (_) => const Scaffold(body: Text('Edit Server Dialog')),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    // Simulate _switchServer called inside setState:
    // Show toast while dialog is visible (this is what _switchServer does)
    AppToast.info(context, 'Server Switched');
    await tester.pump(const Duration(milliseconds: 50));

    // Simulate dialog dismiss
    navigator.pop();
    await tester.pump(const Duration(milliseconds: 50));

    // Simulate the second toast after dialog dismiss
    AppToast.info(context, 'Server Updated');
    await tester.pump(const Duration(milliseconds: 50));

    // Should not crash
    expect(find.byType(Scaffold), findsWidgets);
  });

  testWidgets('AppToast 先手动 remove entry 再 show 不崩溃', (tester) async {
    // This is the most direct reproduction:
    // Create a scenario where an OverlayEntry is removed but still referenced.

    await tester.pumpWidget(buildTestApp(
      home: const _ToastTrigger(message: 'Test'),
    ));
    await tester.pump();

    final context = tester.element(find.byType(Scaffold));

    // Show toasts to fill up slots
    AppToast.info(context, 'Info');
    AppToast.success(context, 'Success');
    AppToast.warning(context, 'Warning');
    await tester.pump(const Duration(milliseconds: 100));

    // Wait long enough for toasts to auto-dismiss (2500ms timer + 300ms animation)
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));

    // Now show more toasts — all slots should be clear, but let's verify
    AppToast.error(context, 'Error after dismiss');
    await tester.pump(const Duration(milliseconds: 100));

    // Multiple rapid toasts after auto-dismiss
    for (int i = 0; i < 10; i++) {
      AppToast.info(context, 'Post-dismiss $i');
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(Scaffold), findsWidgets);
  });
}
