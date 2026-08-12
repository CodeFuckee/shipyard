import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// SSE（Server-Sent Events）客户端 — 原生平台（Android/iOS/macOS/鸿蒙）。
///
/// 基于 dart:io HttpClient 流式读取响应体，按 SSE 空行分帧输出。
/// 支持自定义请求头（X-API-Key）与忽略自签名证书。
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
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      if (ignoreSsl) {
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
      }
      try {
        final request = await client.postUrl(uri);
        headers.forEach((key, value) => request.headers.set(key, value));
        if (body != null && body.isNotEmpty) {
          request.write(body);
        }
        final response = await request.close();
        if (response.statusCode != 200) {
          final errBody = await response.transform(utf8.decoder).join();
          controller.addError(
              Exception('HTTP ${response.statusCode}: $errBody'));
          return;
        }
        await for (final frame in _splitFrames(response)) {
          controller.add(frame);
        }
      } catch (e) {
        controller.addError(e);
      } finally {
        client.close();
        controller.close();
      }
    });
  }

  /// 将响应字节流按 SSE 空行（\n\n）切分为帧字符串流。
  static Stream<String> _splitFrames(HttpClientResponse response) {
    final decoder = utf8.decoder;
    return Stream.multi((controller) async {
      var buffer = '';
      await for (final chunk in response) {
        buffer += decoder.convert(chunk);
        while (true) {
          final idx = buffer.indexOf('\n\n');
          if (idx < 0) break;
          final frame = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 2);
          if (frame.isNotEmpty) controller.add(frame);
        }
      }
      if (buffer.trim().isNotEmpty) controller.add(buffer.trim());
      controller.close();
    });
  }
}
