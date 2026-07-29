import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'platform/http_helper.dart';
import 'platform/ws_helper.dart';
import '../models/docker_container.dart';
import '../models/docker_image.dart';
import '../models/docker_network.dart';
import '../models/docker_volume.dart';
import '../models/server_usage.dart';
import '../models/container_file.dart';
import '../models/project.dart';
import '../models/build_log.dart';

class DockerService {
  final String baseUrl;
  final String? apiKey;
  final bool ignoreSsl;
  late final http.Client _client;

  DockerService({required this.baseUrl, this.apiKey, this.ignoreSsl = false}) {
    _client = HttpHelper.createClient(ignoreSsl: ignoreSsl);
  }

  Map<String, String> _authHeaders([Map<String, String>? extra]) {
    final h = <String, String>{};
    if (extra != null) h.addAll(extra);
    if (apiKey != null && apiKey!.isNotEmpty) {
      if (apiKey!.startsWith('eyJ')) {
        h['Authorization'] = 'Bearer $apiKey';
      } else {
        h['X-API-Key'] = apiKey!;
      }
    }
    return h;
  }

  /// Extract a user-friendly error message from the backend response body.
  /// Fallback: a generic description with the HTTP status code.
  String _extractErrorMessage(String responseBody, String fallback, int statusCode) {
    try {
      final decoded = json.decode(responseBody);
      if (decoded is Map<String, dynamic>) {
        // Common backend error field names
        for (final key in ['detail', 'message', 'error', 'msg']) {
          final val = decoded[key];
          if (val != null && val.toString().isNotEmpty) {
            return val.toString();
          }
        }
      }
    } catch (_) {
      // Body is not valid JSON — use it directly if short enough
      if (responseBody.length < 200) {
        return responseBody.trim();
      }
    }
    return '$fallback ($statusCode)';
  }

  Future<List<DockerContainer>> getContainers() async {
    // 确保 baseUrl 没有尾随斜杠
    final cleanBaseUrl = baseUrl.endsWith('/') 
        ? baseUrl.substring(0, baseUrl.length - 1) 
        : baseUrl;
        
    final url = Uri.parse('$cleanBaseUrl/containers/summary');

    final headers = _authHeaders();

    try {
      final response = await _client.get(url, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((json) => DockerContainer.fromJson(json)).toList();
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<List<DockerImage>> getImages() async {
    // 确保 baseUrl 没有尾随斜杠
    final cleanBaseUrl = baseUrl.endsWith('/') 
        ? baseUrl.substring(0, baseUrl.length - 1) 
        : baseUrl;
        
    final url = Uri.parse('$cleanBaseUrl/images');

    final headers = _authHeaders();

    try {
      final response = await _client.get(url, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((json) => DockerImage.fromJson(json)).toList();
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<List<DockerNetwork>> getNetworks() async {
    final cleanBaseUrl = baseUrl.endsWith('/') 
        ? baseUrl.substring(0, baseUrl.length - 1) 
        : baseUrl;
        
    final url = Uri.parse('$cleanBaseUrl/networks');

    final headers = _authHeaders();

    try {
      final response = await _client.get(url, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((json) => DockerNetwork.fromJson(json)).toList();
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<Map<String, dynamic>> getNetwork(String id) async {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final url = Uri.parse('$cleanBaseUrl/networks/$id');

    final headers = _authHeaders();

    try {
      final response = await _client.get(url, headers: headers);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<List<DockerVolume>> getVolumes() async {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final url = Uri.parse('$cleanBaseUrl/volumes');

    final headers = _authHeaders();

    try {
      final response = await _client.get(url, headers: headers);

      if (response.statusCode == 200) {
        final dynamic jsonData = json.decode(response.body);
        List<dynamic> list;
        if (jsonData is Map && jsonData.containsKey('Volumes')) {
           list = jsonData['Volumes'];
        } else if (jsonData is List) {
           list = jsonData;
        } else {
           list = [];
        }
        return list.map((json) => DockerVolume.fromJson(json)).toList();
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<Map<String, dynamic>> getVolume(String name) async {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final url = Uri.parse('$cleanBaseUrl/volumes/$name');

    final headers = _authHeaders();

    try {
      final response = await _client.get(url, headers: headers);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<void> deleteVolume(String name) async {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final url = Uri.parse('$cleanBaseUrl/volumes/$name');

    final headers = _authHeaders();

    try {
      final response = await _client.delete(url, headers: headers);

      if (response.statusCode == 200 || response.statusCode == 204) {
        return;
      } else {
        // Try to parse error message from body if available
        try {
          final body = json.decode(response.body);
          if (body is Map && body.containsKey('message')) {
             throw Exception(body['message']);
          }
        } catch (_) {}
        final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<ServerUsage> getUsage() async {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final url = Uri.parse('$cleanBaseUrl/usage');

    final headers = _authHeaders();

    try {
      final response = await _client.get(url, headers: headers);

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return ServerUsage.fromJson(jsonData);
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<Map<String, dynamic>> getImage(String id) async {
    final cleanBaseUrl = baseUrl.endsWith('/') 
        ? baseUrl.substring(0, baseUrl.length - 1) 
        : baseUrl;
        
    final url = Uri.parse('$cleanBaseUrl/images/$id');

    final headers = _authHeaders();

    try {
      final response = await _client.get(url, headers: headers);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<Map<String, dynamic>> deleteImage(String id) async {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = Uri.parse('$cleanBaseUrl/images/$id');

    final headers = _authHeaders();

    try {
      final response = await _client.delete(url, headers: headers);

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        } else if (decoded is List) {
           return {'status': 'success', 'details': decoded};
        }
        return {'status': 'success'};
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to delete volume', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<Map<String, dynamic>> pullImage(String name, String tag) async {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = Uri.parse('$cleanBaseUrl/images/pull');

    final headers = _authHeaders({'Content-Type': 'application/json'});

    final body = json.encode({
      'image': name,
      'tag': tag,
    });

    try {
      final response = await _client.post(url, headers: headers, body: body);
      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonMap = json.decode(response.body);
        return jsonMap;
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load usage', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<Map<String, dynamic>> getContainer(String id) async {
    final cleanBaseUrl = baseUrl.endsWith('/') 
        ? baseUrl.substring(0, baseUrl.length - 1) 
        : baseUrl;
        
    final url = Uri.parse('$cleanBaseUrl/containers/$id');

    final headers = _authHeaders();

    try {
      final response = await _client.get(url, headers: headers);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<void> _performContainerAction(String id, String action) async {
    final cleanBaseUrl = baseUrl.endsWith('/') 
        ? baseUrl.substring(0, baseUrl.length - 1) 
        : baseUrl;
        
    final url = Uri.parse('$cleanBaseUrl/containers/$id/$action');

    final headers = _authHeaders();

    try {
      final response = await _client.post(url, headers: headers);

      if (response.statusCode != 204 && response.statusCode != 200) {
         final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                 throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }
  
  Future<List<ContainerFile>> getContainerFiles(String id, {String path = '/'}) async {
    final cleanBaseUrl = baseUrl.endsWith('/') 
        ? baseUrl.substring(0, baseUrl.length - 1) 
        : baseUrl;
        
    final url = Uri.parse('$cleanBaseUrl/containers/$id/files').replace(queryParameters: {'path': path});

    final headers = _authHeaders();

    try {
      final response = await _client.get(url, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((json) => ContainerFile.fromJson(json)).toList();
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<String> getContainerFileContent(String id, String path) async {
    final cleanBaseUrl = baseUrl.endsWith('/') 
        ? baseUrl.substring(0, baseUrl.length - 1) 
        : baseUrl;
        
    final url = Uri.parse('$cleanBaseUrl/containers/$id/files').replace(queryParameters: {'path': path});

    final headers = _authHeaders();

    try {
      final response = await _client.get(url, headers: headers);

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonMap = json.decode(response.body);
        return jsonMap['content']?.toString() ?? '';
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<Uint8List> downloadContainerFile(String id, String path) async {
    final cleanBaseUrl = baseUrl.endsWith('/') 
        ? baseUrl.substring(0, baseUrl.length - 1) 
        : baseUrl;
        
    final url = Uri.parse('$cleanBaseUrl/containers/$id/download').replace(queryParameters: {'path': path});

    final headers = _authHeaders();

    try {
      final response = await _client.get(url, headers: headers);

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<void> updateContainerFile(String id, String path, String content) async {
    final cleanBaseUrl = baseUrl.endsWith('/') 
        ? baseUrl.substring(0, baseUrl.length - 1) 
        : baseUrl;
        
    final url = Uri.parse('$cleanBaseUrl/containers/$id/files').replace(queryParameters: {'path': path});

    final headers = _authHeaders({'Content-Type': 'application/json'});

    final body = json.encode({'path':path,'content': content});

    try {
      final response = await _client.put(url, headers: headers, body: body);

      if (response.statusCode != 200 && response.statusCode != 204) {
        final msg = _extractErrorMessage(response.body, 'Failed to download file', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<void> startContainer(String id) => _performContainerAction(id, 'start');
  Future<void> stopContainer(String id) => _performContainerAction(id, 'stop');
  Future<void> killContainer(String id) => _performContainerAction(id, 'kill');
  Future<void> restartContainer(String id) => _performContainerAction(id, 'restart');
  Future<void> pauseContainer(String id) => _performContainerAction(id, 'pause');
  Future<void> resumeContainer(String id) => _performContainerAction(id, 'unpause');
  
  Future<Map<String, dynamic>> runContainer(String command) async {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = Uri.parse('$cleanBaseUrl/containers/run');

    final headers = _authHeaders({'Content-Type': 'application/json'});

    final body = json.encode({'command': command});

    try {
      final response = await _client.post(url, headers: headers, body: body);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        // Try to decode error body if possible
        try {
           final errorBody = json.decode(response.body);
           if (errorBody is Map<String, dynamic> && errorBody.containsKey('detail')) {
             throw Exception(errorBody['detail']);
           }
        } catch (_) {}
        final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<void> removeContainer(String id, {bool force = false}) async {
      final cleanBaseUrl = baseUrl.endsWith('/') 
        ? baseUrl.substring(0, baseUrl.length - 1) 
        : baseUrl;
        
    final url = Uri.parse('$cleanBaseUrl/containers/$id').replace(
      queryParameters: {'force': force.toString()},
    );

    final headers = _authHeaders();

    try {
      final response = await _client.delete(url, headers: headers);

      if (response.statusCode != 204 && response.statusCode != 200) {
          final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                  throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<List<String>> getStacks() async {
    final cleanBaseUrl = baseUrl.endsWith('/') 
        ? baseUrl.substring(0, baseUrl.length - 1) 
        : baseUrl;
        
    final url = Uri.parse('$cleanBaseUrl/stacks');

    final headers = _authHeaders();

    try {
      final response = await _client.get(url, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map<String>((item) {
          if (item is String) return item;
          if (item is Map) {
             return (item['Name'] ?? item['name'] ?? '').toString();
          }
          return '';
        }).where((s) => s.isNotEmpty).toList();
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<List<DockerContainer>> getStackContainers(String stackName) async {
    final cleanBaseUrl = baseUrl.endsWith('/') 
        ? baseUrl.substring(0, baseUrl.length - 1) 
        : baseUrl;
        
    final url = Uri.parse('$cleanBaseUrl/stacks/$stackName/containers');

    final headers = _authHeaders();

    try {
      final response = await _client.get(url, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((json) => DockerContainer.fromJson(json)).toList();
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<Map<String, dynamic>> getGitVersion() async {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = Uri.parse('$cleanBaseUrl/git/version');

    final headers = _authHeaders();

    try {
      final response = await _client.get(url, headers: headers);
      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonMap = json.decode(response.body);
        return jsonMap;
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<Map<String, dynamic>> getSystemInfo() async {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = Uri.parse('$cleanBaseUrl/info');

    final headers = _authHeaders();

    try {
      final response = await _client.get(url, headers: headers);
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<WebSocketChannel> connectToEvents() async {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    String httpUrl;
    if (cleanBaseUrl.startsWith('https')) {
      httpUrl = '$cleanBaseUrl/ws/events';
    } else if (cleanBaseUrl.startsWith('http')) {
      httpUrl = '$cleanBaseUrl/ws/events';
    } else {
      httpUrl = 'http://$cleanBaseUrl/ws/events';
    }

    if (apiKey != null && apiKey!.isNotEmpty) {
      httpUrl = '$httpUrl?api_key=${Uri.encodeComponent(apiKey!)}';
    }

    if(kDebugMode){
      final logUrl = apiKey != null && apiKey!.isNotEmpty
          ? httpUrl.replaceFirst(apiKey!, '***')
          : httpUrl;
      print('WebSocket URL: $logUrl');
    }
    final uri = Uri.parse(httpUrl);
    return WsHelper.connectUpgrade(uri, apiKey: apiKey, ignoreSsl: ignoreSsl);
  }

  Stream<dynamic> pullImageWs(String name, String tag) async* {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    String wsUrl = cleanBaseUrl.replaceFirst('http', 'ws');
    if (cleanBaseUrl.startsWith('https')) {
      wsUrl = cleanBaseUrl.replaceFirst('https', 'wss');
    } else if (!cleanBaseUrl.startsWith('http')) {
      wsUrl = 'ws://$cleanBaseUrl';
    } else {
      wsUrl = cleanBaseUrl.replaceFirst('http', 'ws');
    }

    wsUrl = '$wsUrl/ws/images/pull?api_key=$apiKey';

    final headers = _authHeaders();

    final channel = await WsHelper.connectDirect(
      Uri.parse(wsUrl),
      headers: headers,
      ignoreSsl: ignoreSsl,
    );

    final request = json.encode({
      'image': name,
      'tag': tag,
    });
    channel.sink.add(request);

    try {
      await for (final message in channel.stream) {
        if (message is String) {
          try {
            yield json.decode(message);
          } catch (_) {
            yield {'message': message};
          }
        } else {
          yield {'message': message.toString()};
        }
      }
    } catch (e) {
      yield {'error': e.toString()};
    } finally {
      channel.sink.close();
    }
  }

  Future<String> getContainerLogs(String id) async {
    final cleanBaseUrl = baseUrl.endsWith('/') 
        ? baseUrl.substring(0, baseUrl.length - 1) 
        : baseUrl;
        
    final url = Uri.parse('$cleanBaseUrl/containers/$id/logs?stdout=1&stderr=1&tail=100&timestamps=0');

    final headers = _authHeaders();

    try {
      final response = await _client.get(url, headers: headers);

      if (response.statusCode == 200) {
        // Try parsing as JSON first (custom API wrapper case)
        try {
          final jsonResponse = json.decode(response.body);
          if (jsonResponse is Map && jsonResponse.containsKey('logs')) {
             return jsonResponse['logs'].toString();
          }
        } catch (_) {
          // Not JSON, proceed to standard binary parsing
        }

        return _parseDockerLogs(response.bodyBytes);
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  String _parseDockerLogs(Uint8List bytes) {
    final buffer = StringBuffer();
    int index = 0;
    final ansiRegex = RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'); // Regex to strip ANSI codes

    while (index < bytes.length) {
      if (index + 8 > bytes.length) {
        String remaining = utf8.decode(bytes.sublist(index), allowMalformed: true);
        buffer.write(remaining.replaceAll(ansiRegex, ''));
        break;
      }
      
      final type = bytes[index];
      // Check for Docker header pattern: [StreamType] 0 0 0 [Size...]
      if ((type == 1 || type == 2) && 
          bytes[index+1] == 0 && 
          bytes[index+2] == 0 && 
          bytes[index+3] == 0) {
          
        int size = (bytes[index + 4] << 24) |
                   (bytes[index + 5] << 16) |
                   (bytes[index + 6] << 8) |
                   (bytes[index + 7]);

        index += 8; // Skip header

        if (index + size > bytes.length) {
           size = bytes.length - index;
        }

        if (size > 0) {
          String chunk = utf8.decode(bytes.sublist(index, index + size), allowMalformed: true);
          buffer.write(chunk.replaceAll(ansiRegex, ''));
          index += size;
        }
      } else {
        // Not a header (maybe TTY mode), treat as raw text
        String chunk = utf8.decode(bytes.sublist(index), allowMalformed: true);
        buffer.write(chunk.replaceAll(ansiRegex, ''));
        break;
      }
    }
    return buffer.toString();
  }

  Future<Map<String, dynamic>> getAvailablePorts() async {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final url = Uri.parse('$cleanBaseUrl/ports/available');

    final headers = _authHeaders();

    try {
      final response = await _client.get(url, headers: headers);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load containers', response.statusCode);
                throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  // -------------------- Projects --------------------

  Future<List<Project>> getProjects() async {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = Uri.parse('$cleanBaseUrl/projects');

    final headers = _authHeaders();

    try {
      final response = await _client.get(url, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((json) => Project.fromJson(json)).toList();
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load projects', response.statusCode);
        throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<Project> createProject(String name, String description) async {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = Uri.parse('$cleanBaseUrl/projects');

    final headers = _authHeaders({'Content-Type': 'application/json'});

    final body = json.encode({
      'name': name,
      'description': description,
    });

    try {
      final response = await _client.post(url, headers: headers, body: body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        return Project.fromJson(json.decode(response.body));
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to create project', response.statusCode);
        throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<Project> getProject(String id) async {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = Uri.parse('$cleanBaseUrl/projects/$id');

    final headers = _authHeaders();

    try {
      final response = await _client.get(url, headers: headers);

      if (response.statusCode == 200) {
        return Project.fromJson(json.decode(response.body));
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load project', response.statusCode);
        throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<void> deleteProject(String id) async {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = Uri.parse('$cleanBaseUrl/projects/$id');

    final headers = _authHeaders();

    try {
      final response = await _client.delete(url, headers: headers);

      if (response.statusCode != 204 && response.statusCode != 200) {
        final msg = _extractErrorMessage(response.body, 'Failed to delete project', response.statusCode);
        throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  // -------------------- Project Files --------------------

  Future<String> getProjectFile(String projectId, String filename) async {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = Uri.parse('$cleanBaseUrl/projects/$projectId/files/$filename');

    final headers = _authHeaders();

    try {
      final response = await _client.get(url, headers: headers);

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonMap = json.decode(response.body);
        return jsonMap['content']?.toString() ?? '';
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to load project file', response.statusCode);
        throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<void> updateProjectFile(String projectId, String filename, String content) async {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = Uri.parse('$cleanBaseUrl/projects/$projectId/files/$filename');

    final headers = _authHeaders({'Content-Type': 'application/json'});

    final body = json.encode({'content': content});

    try {
      final response = await _client.put(url, headers: headers, body: body);

      if (response.statusCode != 200 && response.statusCode != 204) {
        final msg = _extractErrorMessage(response.body, 'Failed to save project file', response.statusCode);
        throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  // -------------------- Project Build --------------------

  Future<Map<String, dynamic>> triggerBuild(String projectId) async {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = Uri.parse('$cleanBaseUrl/projects/$projectId/build');

    final headers = _authHeaders({'Content-Type': 'application/json'});

    try {
      final response = await _client.post(url, headers: headers);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to trigger build', response.statusCode);
        throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Stream<BuildLog> getBuildLogs(String projectId) async* {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    String wsUrl = cleanBaseUrl.replaceFirst('http', 'ws');
    if (cleanBaseUrl.startsWith('https')) {
      wsUrl = cleanBaseUrl.replaceFirst('https', 'wss');
    } else if (!cleanBaseUrl.startsWith('http')) {
      wsUrl = 'ws://$cleanBaseUrl';
    } else {
      wsUrl = cleanBaseUrl.replaceFirst('http', 'ws');
    }

    wsUrl = '$wsUrl/ws/projects/$projectId/build/logs?api_key=$apiKey';

    final headers = _authHeaders();

    final channel = await WsHelper.connectDirect(
      Uri.parse(wsUrl),
      headers: headers,
      ignoreSsl: ignoreSsl,
    );

    try {
      await for (final message in channel.stream) {
        if (message is String) {
          try {
            yield BuildLog.fromJson(json.decode(message));
          } catch (_) {
            yield BuildLog(rawMessage: message, isDone: false);
          }
        } else {
          yield BuildLog(rawMessage: message.toString(), isDone: false);
        }
      }
    } catch (e) {
      yield BuildLog(error: e.toString(), isDone: true);
    } finally {
      channel.sink.close();
    }
  }

  // -------------------- Project Up / Down --------------------

  Future<Map<String, dynamic>> triggerProjectUp(String projectId) async {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = Uri.parse('$cleanBaseUrl/projects/$projectId/up');

    final headers = _authHeaders({'Content-Type': 'application/json'});

    try {
      final response = await _client.post(url, headers: headers);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to start project', response.statusCode);
        throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }

  Future<Map<String, dynamic>> triggerProjectDown(String projectId) async {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = Uri.parse('$cleanBaseUrl/projects/$projectId/down');

    final headers = _authHeaders({'Content-Type': 'application/json'});

    try {
      final response = await _client.post(url, headers: headers);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final msg = _extractErrorMessage(response.body, 'Failed to stop project', response.statusCode);
        throw Exception(msg);
      }
    } catch (e) {
      throw e is Exception ? e : Exception('Network error');
    }
  }
}
