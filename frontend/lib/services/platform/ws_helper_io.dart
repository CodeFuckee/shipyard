import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

class WsHelper {
  /// 直接 WebSocket 连接（ws:// 或 wss:// 协议）
  static Future<WebSocketChannel> connectDirect(
    Uri uri, {
    Map<String, String>? headers,
    bool ignoreSsl = false,
  }) async {
    if (ignoreSsl) {
      final client = HttpClient();
      client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
      final ws = await WebSocket.connect(uri.toString(), headers: headers, customClient: client);
      return IOWebSocketChannel(ws);
    }
    return IOWebSocketChannel.connect(uri, headers: headers);
  }

  /// 通过 HTTP 升级连接 WebSocket（http:// 或 https:// 协议，手动握手）
  static Future<WebSocketChannel> connectUpgrade(
    Uri httpUri, {
    String? apiKey,
    bool ignoreSsl = false,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    if (ignoreSsl) {
      client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    }

    final request = await client.openUrl('GET', httpUri);
    request.headers.set('Connection', 'Upgrade');
    request.headers.set('Upgrade', 'websocket');
    request.headers.set('Sec-WebSocket-Version', '13');
    final rng = Random();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    final key = base64Encode(bytes);
    request.headers.set('Sec-WebSocket-Key', key);

    if (apiKey != null && apiKey.isNotEmpty) {
      if (apiKey.startsWith('eyJ')) {
        request.headers.set('Authorization', 'Bearer $apiKey');
      } else {
        request.headers.set('X-API-Key', apiKey);
      }
    }

    final response = await request.close();
    if (response.statusCode == 101) {
      final socket = await response.detachSocket();
      final ws = WebSocket.fromUpgradedSocket(socket, serverSide: false);
      return IOWebSocketChannel(ws);
    } else {
      final body = await response.transform(utf8.decoder).join();
      throw Exception('WebSocket upgrade failed: HTTP ${response.statusCode}\n$body');
    }
  }
}
