import 'package:flutter_test/flutter_test.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_portainer_flutter_module/screens/container_details_screen.dart';
import 'test_utils.dart';

void main() {
  testWidgets('未传入 onBack 时不显示返回按钮', (tester) async {
    await tester.pumpWidget(buildTestApp(
      home: ContainerDetailsScreen(
        containerId: 'test-id',
        containerName: 'Test Container',
        apiUrl: 'http://localhost:2375',
        apiKey: 'test-key',
        ignoreSsl: true,
        // onBack is not provided
      ),
    ));
    await tester.pump();

    // 不应该有返回按钮
    expect(find.byIcon(RemixIcon.arrowLeftLine), findsNothing);
  });

  testWidgets('传入 onBack 时显示返回按钮', (tester) async {
    await tester.pumpWidget(buildTestApp(
      home: ContainerDetailsScreen(
        containerId: 'test-id',
        containerName: 'Test Container',
        apiUrl: 'http://localhost:2375',
        apiKey: 'test-key',
        ignoreSsl: true,
        onBack: () {},
      ),
    ));
    await tester.pump();

    // 应该有返回按钮
    expect(find.byIcon(RemixIcon.arrowLeftLine), findsOneWidget);
  });

  testWidgets('点击返回按钮触发 onBack 回调', (tester) async {
    bool backCalled = false;

    await tester.pumpWidget(buildTestApp(
      home: ContainerDetailsScreen(
        containerId: 'test-id',
        containerName: 'Test Container',
        apiUrl: 'http://localhost:2375',
        apiKey: 'test-key',
        ignoreSsl: true,
        onBack: () {
          backCalled = true;
        },
      ),
    ));
    await tester.pump();

    // 点击返回按钮
    await tester.tap(find.byIcon(RemixIcon.arrowLeftLine));
    await tester.pump();

    expect(backCalled, isTrue);
  });

  testWidgets('返回按钮在 AppBar leading 位置', (tester) async {
    await tester.pumpWidget(buildTestApp(
      home: ContainerDetailsScreen(
        containerId: 'test-id',
        containerName: 'Test Container',
        apiUrl: 'http://localhost:2375',
        apiKey: 'test-key',
        ignoreSsl: true,
        onBack: () {},
      ),
    ));
    await tester.pump();

    // 验证标题和返回按钮同时存在
    expect(find.text('Test Container'), findsOneWidget);
    expect(find.byIcon(RemixIcon.arrowLeftLine), findsOneWidget);
  });

  testWidgets('独立使用时不显示返回按钮（无 onBack）', (tester) async {
    // 模拟从导航 push 进入的场景，不带 onBack
    await tester.pumpWidget(buildTestApp(
      home: ContainerDetailsScreen(
        containerId: 'test-id',
        containerName: 'Standalone Container',
        apiUrl: 'http://localhost:2375',
        apiKey: 'test-key',
        ignoreSsl: true,
      ),
    ));
    await tester.pump();

    // 独立使用时不应有返回按钮
    expect(find.byIcon(RemixIcon.arrowLeftLine), findsNothing);
    expect(find.text('Standalone Container'), findsOneWidget);
  });
}
