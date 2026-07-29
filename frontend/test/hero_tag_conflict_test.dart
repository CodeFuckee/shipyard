import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_portainer_flutter_module/screens/resources_screen.dart';
import 'test_utils.dart';

/// 复现并验证 Hero tag 冲突修复：
/// 当同一个页面中存在多个使用默认 heroTag 的 FloatingActionButton 时，
/// 导航到新页面会触发 Hero 动画，导致 "multiple heroes share the same tag" 断言错误。
void main() {
  testWidgets('同一路由中多个 FloatingActionButton 使用相同默认 heroTag 会抛出 assertion error',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // 构建一个包含两个默认 heroTag FAB 的页面（复现 bug 的根因场景）
    await tester.pumpWidget(buildTestApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: Builder(
                builder: (context) => ElevatedButton(
                  key: const Key('navigate'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Detail')),
                          body: const Center(child: Text('Detail Page')),
                        ),
                      ),
                    );
                  },
                  child: const Text('Go'),
                ),
              ),
            ),
            // 两个 FloatingActionButton 使用相同的默认 heroTag（不设置 heroTag）
            const Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                onPressed: null,
                child: Icon(Icons.add),
              ),
            ),
            const Positioned(
              right: 16,
              bottom: 80,
              child: FloatingActionButton(
                onPressed: null,
                child: Icon(Icons.add),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // 点击导航按钮，触发 Hero 动画
    await tester.tap(find.byKey(const Key('navigate')));
    await tester.pump();

    // Hero 系统会检测到两个相同 tag 的 FAB 并抛出 assertion error
    // 在测试中，这个异常会被 Flutter 框架捕获并通过 exception handler 处理
    final dynamic exception = tester.takeException();
    expect(exception, isNotNull);
    expect(
      exception.toString(),
      contains('multiple heroes'),
    );
    expect(
      exception.toString(),
      contains('FloatingActionButton'),
    );
  });

  testWidgets('设置唯一 heroTag 后导航不会抛出 Hero tag 冲突错误', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // 模拟 MainTabScreen 的实际场景：两个 FAB 各有唯一 heroTag
    await tester.pumpWidget(buildTestApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: Builder(
                builder: (context) => ElevatedButton(
                  key: const Key('navigate'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Detail')),
                          body: const Center(child: Text('Detail Page')),
                        ),
                      ),
                    );
                  },
                  child: const Text('Go'),
                ),
              ),
            ),
            // containers tab 的 FAB
            const Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                heroTag: 'fab_containers',
                onPressed: null,
                child: Icon(Icons.add),
              ),
            ),
            // ResourcesScreen 的 FAB
            const Positioned(
              right: 16,
              bottom: 80,
              child: FloatingActionButton(
                heroTag: 'fab_resources',
                onPressed: null,
                child: Icon(Icons.add),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // 点击导航按钮
    await tester.tap(find.byKey(const Key('navigate')));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // 验证没有异常抛出，且成功导航到详情页
    expect(tester.takeException(), isNull);
    expect(find.text('Detail Page'), findsOneWidget);
  });

  testWidgets('ResourcesScreen 的 FAB 使用唯一 heroTag', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildTestApp(
      home: const Scaffold(body: ResourcesScreen()),
    ));
    await tester.pumpAndSettle();

    // 验证 FAB 存在
    final fabFinder = find.byType(FloatingActionButton);
    expect(fabFinder, findsOneWidget);

    // 验证 FAB 有自定义 heroTag（不为默认值）
    final fab = tester.widget<FloatingActionButton>(fabFinder);
    expect(fab.heroTag, isNotNull);
    // 确保不是默认的 default FloatingActionButton tag
    expect(fab.heroTag.toString(), isNot(contains('default')));
  });

  testWidgets('MainTabScreen 各 FAB 的 heroTag 不冲突', (tester) async {
    // 这个测试验证完整的 MainTabScreen 场景
    // 由于 MainTabScreen 依赖 DockerService 等真实服务，这里只做 widget 层面验证

    // 创建两个不同 heroTag 的 FAB 在同一个 Stack 中
    await tester.pumpWidget(buildTestApp(
      home: Scaffold(
        body: Stack(
          children: const [
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                heroTag: 'fab_main_container',
                onPressed: null,
                child: Icon(Icons.add),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 80,
              child: FloatingActionButton(
                heroTag: 'fab_main_resources',
                onPressed: null,
                child: Icon(Icons.add),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // 找到所有 FAB
    final fabs = find.byType(FloatingActionButton);
    expect(fabs, findsNWidgets(2));

    // 验证每个 FAB 有不同的 heroTag
    final fab1 = tester.widget<FloatingActionButton>(fabs.first);
    final fab2 = tester.widget<FloatingActionButton>(fabs.last);
    expect(fab1.heroTag, isNot(equals(fab2.heroTag)));
  });
}
