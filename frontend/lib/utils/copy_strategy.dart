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
  ///
  /// 浏览器环境不可控：clipboard API 可能因权限/安全上下文抛异常，
  /// execCommand 也可能在部分浏览器（如 iOS Safari / 部分 WebView）中
  /// 直接抛 JS 异常。任何写入路径抛异常都必须在此兜底为"复制失败"，
  /// 绝不能让异常沿异步链传播为未处理的 Future error。
  Future<bool> copy(String text) async {
    if (probeApi()) {
      try {
        final ok = await writeViaApi(text);
        if (ok) return true;
      } catch (_) {
        // 浏览器拒绝/异常写入时回退到 execCommand
      }
    }
    try {
      return writeViaExecCommand(text);
    } catch (_) {
      return false;
    }
  }
}
