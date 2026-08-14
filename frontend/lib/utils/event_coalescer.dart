import 'dart:async';

/// 高频事件合并器：将在 [interval] 窗口内到达的事件合并，
/// 窗口结束时一次性调用 [onFlush] 处理全部事件。
///
/// 用于 WebSocket Docker 事件等高频来源：逐条事件触发 setState
/// 会导致 item 多的列表高频整体重建，与滚动叠加造成卡顿
/// （issue #30）。合并后事件风暴只触发一次重建。
class EventCoalescer<T> {
  final Duration interval;
  final void Function(List<T> events) onFlush;

  final List<T> _pending = <T>[];
  Timer? _timer;

  EventCoalescer({required this.interval, required this.onFlush});

  /// 添加一条事件；窗口结束（距首条事件 [interval]）时统一 flush。
  void add(T event) {
    _pending.add(event);
    _timer ??= Timer(interval, _flush);
  }

  void _flush() {
    _timer = null;
    if (_pending.isEmpty) return;
    final events = List<T>.from(_pending);
    _pending.clear();
    onFlush(events);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}
