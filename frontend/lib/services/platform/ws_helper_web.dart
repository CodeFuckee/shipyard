import 'package:web_socket_channel/web_socket_channel.dart';

class WsHelper {
  /// Web 端直接 WebSocket 连接
  static Future<WebSocketChannel> connectDirect(
    Uri uri, {
    Map<String, String>? headers,
    bool ignoreSsl = false,
  }) async {
    return WebSocketChannel.connect(uri);
  }

  /// Web 端通过 URL 连接（将 http 转为 ws 协议）
  static Future<WebSocketChannel> connectUpgrade(
    Uri httpUri, {
    String? apiKey,
    bool ignoreSsl = false,
  }) async {
    String wsUrl = httpUri.toString();
    if (wsUrl.startsWith('https')) {
      wsUrl = wsUrl.replaceFirst('https', 'wss');
    } else if (wsUrl.startsWith('http')) {
      wsUrl = wsUrl.replaceFirst('http', 'ws');
    }
    return WebSocketChannel.connect(Uri.parse(wsUrl));
  }
}
