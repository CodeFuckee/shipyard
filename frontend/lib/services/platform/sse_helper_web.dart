import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

/// SSE（Server-Sent Events）客户端 — Web 平台。
///
/// package:http 的 Web 实现基于 XMLHttpRequest，不支持流式读取；EventSource
/// 又不支持自定义请求头（X-API-Key 认证需要）。因此使用 fetch API +
/// ReadableStream 手动读取并解析 SSE 帧。
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
        final response = await html.window.fetch(
          uri.toString(),
          {'method': 'POST', 'headers': headers, 'body': body ?? ''},
        );
        if (response.status != 200) {
          final errBody = await response.text();
          controller.addError(
              Exception('HTTP ${response.status}: $errBody'));
          return;
        }
        final reader = response.body?.getReader();
        if (reader == null) {
          controller.close();
          return;
        }
        final decoder = utf8.decoder;
        var buffer = '';
        while (true) {
          final result = await reader.read();
          if (result.done) break;
          buffer += _bytesToText(result.value, decoder);
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

  /// 将 ReadableStream 读出的 chunk 转为文本（兼容 Uint8List / ByteBuffer）。
  static String _bytesToText(dynamic value, Utf8Decoder decoder) {
    if (value is String) return value;
    if (value is List<int>) return decoder.convert(value);
    if (value is ByteBuffer) return decoder.convert(value.asUint8List());
    if (value is Uint8List) return decoder.convert(value);
    return '';
  }
}
