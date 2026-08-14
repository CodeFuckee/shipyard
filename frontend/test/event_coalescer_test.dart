import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_portainer_flutter_module/utils/event_coalescer.dart';

/// issue #30（次因）：WebSocket Docker 事件逐条触发 setState 全列表重建。
/// 生产服务器事件频繁时（容器 start/stop/die 等），item 多的列表被
/// 高频整体重建，与滚动叠加造成掉帧卡顿。
///
/// 修复：引入 EventCoalescer，将时间窗口内到达的高频事件合并为
/// 一次 flush，事件风暴下只触发一次列表重建。
/// （当前该工具类不存在 → 本测试编译失败，即复现"无合并机制"的缺陷。）
void main() {
  testWidgets('高频事件在合并窗口内只 flush 一次', (tester) async {
    final flushes = <List<int>>[];
    final coalescer = EventCoalescer(
      interval: const Duration(milliseconds: 300),
      onFlush: (events) => flushes.add(List<int>.from(events)),
    );

    // 窗口内连发 50 条事件
    for (var i = 0; i < 50; i++) {
      coalescer.add(i);
      await tester.pump(const Duration(milliseconds: 5));
    }
    expect(flushes, isEmpty,
        reason: '窗口未结束前不应 flush，避免逐条重建列表');

    // 窗口结束 → 合并为一次 flush，且保留全部事件
    await tester.pump(const Duration(milliseconds: 300));
    expect(flushes.length, 1, reason: '50 条事件应合并为一次 flush');
    expect(flushes.single.length, 50, reason: '合并 flush 应包含全部事件');

    // 新窗口内再来一条 → 再次 flush
    coalescer.add(99);
    await tester.pump(const Duration(milliseconds: 300));
    expect(flushes.length, 2, reason: '新窗口的事件应触发第二次 flush');
    expect(flushes.last, [99]);
  });

  testWidgets('间隔超过窗口的事件各自独立 flush', (tester) async {
    final flushes = <List<int>>[];
    final coalescer = EventCoalescer(
      interval: const Duration(milliseconds: 300),
      onFlush: (events) => flushes.add(List<int>.from(events)),
    );

    coalescer.add(1);
    await tester.pump(const Duration(milliseconds: 400));
    coalescer.add(2);
    await tester.pump(const Duration(milliseconds: 400));

    expect(flushes.length, 2, reason: '跨窗口事件应独立 flush');
    expect(flushes[0], [1]);
    expect(flushes[1], [2]);
  });
}
