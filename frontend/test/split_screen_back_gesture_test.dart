import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/services/harmonyos_platform.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

Widget _buildTestMaterialApp({required Widget home}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('zh')],
    home: home,
  );
}

// Minimal WidgetsBindingObserver for testing didPopRoute
class _TestPage extends StatefulWidget {
  final bool hasDetail;
  final VoidCallback onBack;

  const _TestPage({required this.hasDetail, required this.onBack});

  @override
  State<_TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<_TestPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    if (widget.hasDetail) {
      widget.onBack();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.hasDetail,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.hasDetail) {
          widget.onBack();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Page')),
        body: const Center(child: Text('Content')),
      ),
    );
  }
}

void main() {
  group('PopScope 拦截系统返回', () {
    testWidgets('canPop=false 阻止返回', (tester) async {
      await tester.pumpWidget(_buildTestMaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('Detail')),
                        body: PopScope(
                          canPop: false,
                          onPopInvokedWithResult: (didPop, result) {},
                          child: const Center(child: Text('Intercepted')),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pump();

      expect(find.text('Detail'), findsOneWidget);
    });

    testWidgets('canPop=true 时正常返回', (tester) async {
      await tester.pumpWidget(_buildTestMaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PopScope(
                        canPop: true,
                        child: Scaffold(
                          appBar: AppBar(title: const Text('Detail')),
                          body: const Center(child: Text('Allowed')),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Open'), findsOneWidget);
    });
  });

  group('didPopRoute — ohos 返回手势兜底', () {
    testWidgets('hasDetail=true 时 didPopRoute 返回 true 并触发 onBack', (tester) async {
      bool backCalled = false;

      await tester.pumpWidget(_buildTestMaterialApp(
        home: _TestPage(
          hasDetail: true,
          onBack: () => backCalled = true,
        ),
      ));
      await tester.pump();

      // Call didPopRoute (simulating ohos system back gesture)
      final state = tester.state<_TestPageState>(find.byType(_TestPage));
      final result = await state.didPopRoute();

      expect(result, isTrue);
      expect(backCalled, isTrue);
    });

    testWidgets('hasDetail=false 时 didPopRoute 返回 false', (tester) async {
      bool backCalled = false;

      await tester.pumpWidget(_buildTestMaterialApp(
        home: _TestPage(
          hasDetail: false,
          onBack: () => backCalled = true,
        ),
      ));
      await tester.pump();

      final state = tester.state<_TestPageState>(find.byType(_TestPage));
      final result = await state.didPopRoute();

      expect(result, isFalse);
      expect(backCalled, isFalse);
    });
  });

  group('HarmonyosPlatform.exitSplitScreen — 分屏退出', () {
    const channelName = 'com.chenkaidi.mobileportainer/harmonyos';

    testWidgets('原生返回 true 时 exitSplitScreen 返回 true', (tester) async {
      // 设置 mock：原生端返回 true（在分屏中，成功退出）
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async {
          if (call.method == 'exitSplitScreen') return true;
          return null;
        },
      );

      final result = await HarmonyosPlatform.exitSplitScreen();
      expect(result, isTrue);

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(channelName),
        null,
      );
    });

    testWidgets('原生返回 false 时 exitSplitScreen 返回 false', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async {
          if (call.method == 'exitSplitScreen') return false;
          return null;
        },
      );

      final result = await HarmonyosPlatform.exitSplitScreen();
      expect(result, isFalse);

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(channelName),
        null,
      );
    });

    testWidgets('原生端未实现方法时 exitSplitScreen 返回 false（安全兜底）', (tester) async {
      // 设置 mock：原生端不识别 exitSplitScreen 方法，返回 null
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async => null,
      );

      final result = await HarmonyosPlatform.exitSplitScreen();
      expect(result, isFalse);

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(channelName),
        null,
      );
    });
  });

  group('分屏状态下返回手势优先级', () {
    const channelName = 'com.chenkaidi.mobileportainer/harmonyos';

    testWidgets('exitSplitScreen 优先于 handler 被调用', (tester) async {
      // 模拟原生端 onBackPressed 调用场景：
      // 用独立的 MethodChannel 验证 exitSplitScreen 被原生端正确处理
      bool exitSplitCalled = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async {
          if (call.method == 'exitSplitScreen') {
            exitSplitCalled = true;
            return true; // 在分屏中
          }
          return null;
        },
      );

      // 模拟 BackPressService 收到 onBackPressed 后的处理逻辑
      // （与 BackPressService 中的实现一致）
      bool handlerCalled = false;
      final exited = await HarmonyosPlatform.exitSplitScreen();
      if (!exited) {
        handlerCalled = true;
      }

      expect(exitSplitCalled, isTrue);
      expect(exited, isTrue);
      expect(handlerCalled, isFalse); // handler 不应被调用，因为已退出分屏

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(channelName),
        null,
      );
    });

    testWidgets('不在分屏时 handler 正常触发', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async {
          if (call.method == 'exitSplitScreen') return false;
          return null;
        },
      );

      // 不在分屏时，handler 应正常执行
      bool handlerCalled = false;
      final exited = await HarmonyosPlatform.exitSplitScreen();
      if (!exited) {
        handlerCalled = true;
      }

      expect(exited, isFalse);
      expect(handlerCalled, isTrue);

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(channelName),
        null,
      );
    });
  });
}
