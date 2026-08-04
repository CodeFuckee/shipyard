import 'dart:js_interop';
import 'copy_strategy.dart';

/// Web 端复制辅助。
///
/// 通过 HTTP（非安全上下文）访问时，浏览器 `navigator.clipboard` 不存在，
/// Flutter 引擎的 `Clipboard.setData` 回退又因异步方法通道往返丢失用户手势
/// 激活而失败。这里在用户手势内**同步**执行 `document.execCommand('copy')`
/// 完成复制（execCommand 不要求安全上下文）；HTTPS 下仍优先走原生
/// `navigator.clipboard.writeText`。
class CopyHelper {
  static final CopyStrategy _strategy = CopyStrategy(
    probeApi: _clipboardApiAvailable,
    writeViaApi: _writeTextViaClipboardApi,
    writeViaExecCommand: _writeTextViaExecCommand,
  );

  static Future<bool> copy(String text) => _strategy.copy(text);

  /// navigator.clipboard 仅在安全上下文（HTTPS/localhost）下存在，
  /// 通过 HTTP 访问时为 null。探测必须同步执行，确保回退路径
  /// 仍在用户手势激活窗口内。
  static bool _clipboardApiAvailable() {
    return _getNavigatorClipboard() != null;
  }

  static Future<bool> _writeTextViaClipboardApi(String text) async {
    final clipboard = _getNavigatorClipboard();
    if (clipboard == null) return false;
    try {
      await clipboard.writeText(text.toJS).toDart;
      return true;
    } catch (_) {
      // 浏览器拒绝写入（权限/上下文变化）时回退 execCommand
      return false;
    }
  }

  /// 隐藏 textarea + execCommand 同步复制（须在用户手势内同步调用）。
  static bool _writeTextViaExecCommand(String text) {
    final document = _getDocument();
    final body = document.body;
    if (body == null) return false;
    final textarea = _JSTextArea(document.createElement('textarea'.toJS));
    textarea.style.setProperty('position'.toJS, 'fixed'.toJS);
    textarea.style.setProperty('top'.toJS, '0'.toJS);
    textarea.style.setProperty('left'.toJS, '0'.toJS);
    textarea.style.setProperty('opacity'.toJS, '0'.toJS);
    textarea.value = text.toJS;
    body.appendChild(textarea);
    textarea.focus();
    textarea.select();
    final ok = document.execCommand('copy'.toJS);
    textarea.remove();
    return ok;
  }
}

/// JS navigator.clipboard
extension type _NavigatorClipboard(JSObject _) implements JSObject {
  external JSPromise<JSString> writeText(JSString text);
}

/// JS document
extension type _JSDocument(JSObject _) implements JSObject {
  external JSObject createElement(JSString tagName);
  external _JSBody? get body;
  external bool execCommand(JSString command);
}

/// JS document.body
extension type _JSBody(JSObject _) implements JSObject {
  external JSObject appendChild(JSObject node);
}

/// JS textarea 元素
extension type _JSTextArea(JSObject _) implements JSObject {
  external set value(JSString value);
  external _JSStyle get style;
  external void focus();
  external void select();
  external void remove();
}

/// JS 元素 style
extension type _JSStyle(JSObject _) implements JSObject {
  external void setProperty(JSString name, JSString value);
}

@JS('navigator.clipboard')
external _NavigatorClipboard? _getNavigatorClipboard();

@JS('document')
external _JSDocument _getDocument();
