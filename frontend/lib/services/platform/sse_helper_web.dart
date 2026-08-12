import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

/// SSE（Server-Sent Events）客户端 — Web 平台。
///
/// package:http 的 Web 实现基于 XMLHttpRequest，不支持流式读取；EventSource
/// 又不支持自定义请求头（X-API-Key 认证需要）。因此直接调用 fetch API +
/// ReadableStream 手动读取并解析 SSE 帧。
///
/// 用 dart:js_interop 手写 JS 映射而非 dart:html：CI 的 Web 构建走
/// dart2wasm（--wasm），dart:html 在 wasm 目标不可用（与
/// file_helper_web.dart 相同的 wasm 兼容模式）。
@JS('fetch')
external JSPromise<JSResponse> _fetch(JSString url, JSObject init);

extension type JSResponse(JSObject _) implements JSObject {
  external int get status;
  external JSPromise<JSString> text();
  external JSReadableStream get body;
}

extension type JSReadableStream(JSObject _) implements JSObject {
  external JSReadableStreamReader getReader();
}

extension type JSReadableStreamReader(JSObject _) implements JSObject {
  external JSPromise<JSReadableStreamReadResult> read();
}

extension type JSReadableStreamReadResult(JSObject _) implements JSObject {
  external bool get done;
  external JSAny? get value;
}

class SseHelper {
  /// 发起 SSE 请求，返回帧字符串流（每帧含 event: / data: 行，不含结尾空行）。
  ///
  /// 非 200 响应、连接异常时以流错误（addError）上报。
  static Stream<String> connect({
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    bool ignoreSsl = false,
  }) {
    return Stream.multi((controller) async {
      try {
        final init = <String, Object?>{
          'method': 'POST',
          'headers': headers,
          if (body != null && body.isNotEmpty) 'body': body,
        }.jsify() as JSObject;
        final response = await _fetch(uri.toString().toJS, init).toDart;
        if (response.status != 200) {
          final errBody = await response.text().toDart;
          controller.addError(Exception('HTTP ${response.status}: $errBody'));
          return;
        }
        final reader = response.body.getReader();
        final decoder = utf8.decoder;
        var buffer = '';
        while (true) {
          final result = await reader.read().toDart;
          if (result.done) break;
          final chunk = _bytesToText(result.value, decoder);
          buffer += chunk;
          while (true) {
            final idx = buffer.indexOf('\n\n');
            if (idx < 0) break;
            final frame = buffer.substring(0, idx).trim();
            buffer = buffer.substring(idx + 2);
            if (frame.isNotEmpty) controller.add(frame);
          }
        }
        if (buffer.trim().isNotEmpty) controller.add(buffer.trim());
      } catch (e) {
        controller.addError(e);
      } finally {
        controller.close();
      }
    });
  }

  /// 将 ReadableStream 读出的 chunk 转为文本（兼容 Uint8Array / ArrayBuffer）。
  static String _bytesToText(JSAny? value, Utf8Decoder decoder) {
    if (value == null) return '';
    if (value is JSUint8Array) return decoder.convert(value.toDart);
    if (value is JSArrayBuffer) {
      return decoder.convert(value.toDart.asUint8List());
    }
    if (value is JSString) return value.toDart;
    return '';
  }
}
