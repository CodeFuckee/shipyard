import 'package:http/http.dart' as http;

class HttpHelper {
  static http.Client createClient({bool ignoreSsl = false}) {
    return http.Client();
  }

  static void closeClient(http.Client client) {
    client.close();
  }
}
