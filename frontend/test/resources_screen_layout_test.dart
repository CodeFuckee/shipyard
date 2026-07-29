import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_portainer_flutter_module/screens/resources_screen.dart';
import 'test_utils.dart';

void main() {
  testWidgets('宽屏模式下导航栏在左侧面板内渲染', (tester) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final navBarKey = GlobalKey();
    await tester.pumpWidget(buildTestApp(
      home: Scaffold(
        body: ResourcesScreen(
          bottomNavBar: Container(key: navBarKey, height: 68, color: Colors.red),
        ),
      ),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byKey(navBarKey), findsOneWidget);
  });

  testWidgets('窄屏模式下不渲染传入的导航栏', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final navBarKey = GlobalKey();
    await tester.pumpWidget(buildTestApp(
      home: Scaffold(
        body: ResourcesScreen(
          bottomNavBar: Container(key: navBarKey, height: 68, color: Colors.red),
        ),
      ),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byKey(navBarKey), findsOneWidget);
  });

  testWidgets('未传入导航栏时页面正常渲染', (tester) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildTestApp(
      home: const Scaffold(body: ResourcesScreen()),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byType(ResourcesScreen), findsOneWidget);
  });
}
