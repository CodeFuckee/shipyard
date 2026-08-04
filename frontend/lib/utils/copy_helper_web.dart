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
  ///
  /// 注意 dart2js 编译规则：`@JS('navigator.clipboard')` 注解在**函数**上会
  /// 编译为 `navigator.clipboard()` **函数调用**（对象/undefined 被调用抛
  /// TypeError）；必须用 `@JS('navigator')` + **getter 声明**（`external T
  /// get name`）+ extension type 属性 getter 链，编译为属性访问，
  /// undefined 安全返回 null。
  static bool _clipboardApiAvailable() {
    return _getNavigator.clipboard != null;
  }

  static Future<bool> _writeTextViaClipboardApi(String text) async {
    final clipboard = _getNavigator.clipboard;
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
  ///
  /// 采用 clipboard.js 同款标准做法提升各浏览器兼容性：
  /// - `readonly` + `contenteditable`：避免 iOS Safari 弹出键盘
  /// - `user-select: text`：防止继承 `user-select: none` 导致 select() 抛异常
  /// - `setSelectionRange` 显式设置选区：iOS Safari 上 select() 可能失效
  /// 部分浏览器中 select()/execCommand() 仍可能同步抛 JS 异常，必须捕获，
  /// 并通过 finally 确保 textarea 从 DOM 移除，避免节点泄漏。
  static bool _writeTextViaExecCommand(String text) {
    final document = _getDocument;
    final body = document.body;
    if (body == null) return false;
    final textarea = _JSTextArea(document.createElement('textarea'.toJS));
    try {
      textarea.readOnly = true.toJS;
      textarea.contentEditable = 'true'.toJS;
      textarea.style.setProperty('position'.toJS, 'fixed'.toJS);
      textarea.style.setProperty('top'.toJS, '-1000px'.toJS);
      textarea.style.setProperty('left'.toJS, '0'.toJS);
      textarea.style.setProperty('fontSize'.toJS, '12pt'.toJS);
      textarea.style.setProperty('userSelect'.toJS, 'text'.toJS);
      textarea.style.setProperty('-webkit-user-select'.toJS, 'text'.toJS);
      textarea.value = text.toJS;
      body.appendChild(textarea);
      textarea.focus();
      textarea.select();
      textarea.setSelectionRange(0.toJS, text.length.toJS);
      return document.execCommand('copy'.toJS);
    } catch (_) {
      return false;
    } finally {
      textarea.remove();
    }
  }
}

/// JS navigator
extension type _Navigator(JSObject _) implements JSObject {
  /// 属性 getter：编译为 `navigator.clipboard` 属性访问，
  /// HTTP 下为 undefined 时安全返回 null（而非抛异常）。
  external _Clipboard? get clipboard;
}

/// JS navigator.clipboard
extension type _Clipboard(JSObject _) implements JSObject {
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
  external set readOnly(JSBoolean value);
  external set contentEditable(JSString value);
  external _JSStyle get style;
  external void focus();
  external void select();
  external void setSelectionRange(JSNumber start, JSNumber end);
  external void remove();
}

/// JS 元素 style
extension type _JSStyle(JSObject _) implements JSObject {
  external void setProperty(JSString name, JSString value);
}

@JS('navigator')
external _Navigator get _getNavigator;

@JS('document')
external _JSDocument get _getDocument;
