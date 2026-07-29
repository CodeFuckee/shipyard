import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class HttpHelper {
  static http.Client createClient({bool ignoreSsl = false}) {
    if (ignoreSsl) {
      final ioc = HttpClient();
      ioc.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
      return IOClient(ioc);
    }
    return http.Client();
  }

  static void closeClient(http.Client client) {
    client.close();
  }
}
