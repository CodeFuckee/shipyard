/// 复制路径决策策略（纯 Dart，不依赖平台 API，便于单元测试）。
///
/// 决策逻辑：浏览器 clipboard API 可用（HTTPS/localhost 等安全上下文）时
/// 优先异步写入；不可用（HTTP 非安全上下文）或写入失败时，回退到同步
/// execCommand 写入——execCommand 不要求安全上下文，但必须在用户手势内
/// **同步**执行才能保留浏览器的 user activation。
typedef ClipboardApiProbe = bool Function();
typedef AsyncClipboardWriter = Future<bool> Function(String text);
typedef SyncClipboardWriter = bool Function(String text);

class CopyStrategy {
  CopyStrategy({
    required this.probeApi,
    required this.writeViaApi,
    required this.writeViaExecCommand,
  });

  /// 探测浏览器 clipboard API 是否可用（HTTP 下 navigator.clipboard 为 null）
  final ClipboardApiProbe probeApi;

  /// 异步写入（navigator.clipboard.writeText）
  final AsyncClipboardWriter writeViaApi;

  /// 同步写入（隐藏 textarea + document.execCommand('copy')）
  final SyncClipboardWriter writeViaExecCommand;

  /// 复制文本，返回是否成功写入剪贴板。
  Future<bool> copy(String text) async {
    if (probeApi()) {
      final ok = await writeViaApi(text);
      if (ok) return true;
    }
    return writeViaExecCommand(text);
  }
}
