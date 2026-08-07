import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/dashboard_screen.dart';
import 'package:mobile_portainer_flutter_module/screens/login_screen.dart';
import 'package:mobile_portainer_flutter_module/services/server_list_storage.dart';
import 'test_utils.dart';

/// 概览页认证错误兜底测试。
///
/// 背景：AuthGate 启动验证（AuthService.isLoggedIn）能拦截"无效 token
/// 直接进入概览页"，但登录后概览页请求仍可能 401（服务器列表条目使用
/// 过期 key、后端重置等）——此时页面直接显示后端原始错误
/// "Invalid API Key or Admin Credentials" 并每 3 秒重试、持续报错。
/// 修复后 _fetchServerData 捕获认证错误时清除凭据回到登录页。
void main() {
  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
    ServerListStorage.debugHttpClient = null;
    HttpOverrides.global = null;
  });

  testWidgets('概览页遇认证错误（401）应清除凭据回到登录页', (tester) async {
    tester.view.physicalSize = const Size(560, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // 已登录凭据（服务器列表为空 → fallback Default Server 用 docker_api_*）
    SharedPreferences.setMockInitialValues({
      'docker_auth_server_url': 'http://127.0.0.1:9000',
      'docker_auth_token': 'token-1',
      'web_backend_url': 'http://127.0.0.1:9000',
      'web_backend_token': 'token-1',
      'docker_api_url': 'http://127.0.0.1:9000',
      'docker_api_key': 'token-1',
    });

    // 服务器列表：后端 401（模拟 web_backend_token 失效）→ 回退本地缓存（空）
    ServerListStorage.debugHttpClient = MockClient(
      (request) async => http.Response(
        '{"detail":"Invalid API Key or Admin Credentials"}',
        401,
      ),
    );

    // /info 返回 401（模拟服务器 API key 失效）
    HttpOverrides.global = _StatusHttpOverrides(401);

    await tester.pumpWidget(buildTestApp(
      home: Scaffold(
        body: DashboardScreen(
          serverListStorageFactory: () => ServerListStorage(forceWeb: true),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    // 认证错误 → 应跳转登录页（清除凭据后）
    expect(find.byType(LoginScreen), findsOneWidget,
        reason: '概览页遇认证错误后应回到登录页，而不是显示原始 401 报错');
    expect(find.textContaining('Invalid API Key'), findsNothing,
        reason: '登录页不应残留后端原始认证错误文本');

    // 凭据已被清除
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('docker_auth_token'), isNull);
    expect(prefs.getString('docker_api_key'), isNull);

    // 卸载 widget 清理 Timer
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('非认证错误（500）不应跳转登录页', (tester) async {
    tester.view.physicalSize = const Size(560, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({
      'docker_auth_server_url': 'http://127.0.0.1:9000',
      'docker_auth_token': 'token-1',
      'web_backend_url': 'http://127.0.0.1:9000',
      'web_backend_token': 'token-1',
      'docker_api_url': 'http://127.0.0.1:9000',
      'docker_api_key': 'token-1',
      // 预置缓存：失败走 isUsingCache 分支（不弹 toast，避免测试环境
      // OverlayEntry 生命周期断言）
      'dashboard_cache_http://127.0.0.1:9000': jsonEncode({
        'totalContainers': 2,
        'runningContainers': 1,
        'stoppedContainers': 1,
        'totalImages': 3,
        'commitDateRaw': null,
        'usage': null,
        'timestamp': 0,
      }),
    });

    ServerListStorage.debugHttpClient = MockClient(
      (request) async => http.Response('[]', 200),
    );

    HttpOverrides.global = _StatusHttpOverrides(500);

    await tester.pumpWidget(buildTestApp(
      home: Scaffold(
        body: DashboardScreen(
          serverListStorageFactory: () => ServerListStorage(forceWeb: true),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    // 500 错误：仍停留在概览页（不跳登录）
    expect(find.byType(LoginScreen), findsNothing,
        reason: '非认证错误不应触发跳转登录页');
    expect(find.byType(DashboardScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

/// 所有请求返回指定状态码的 Fake HTTP 栈（body 为认证错误 JSON）。
class _StatusHttpOverrides extends HttpOverrides {
  final int statusCode;
  _StatusHttpOverrides(this.statusCode);

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _StatusHttpClient(statusCode);
}

class _StatusHttpClient implements HttpClient {
  final int statusCode;
  _StatusHttpClient(this.statusCode);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _StatusHttpRequest(url, statusCode);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _StatusHttpRequest(url, statusCode);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StatusHttpRequest implements HttpClientRequest {
  final Uri url;
  final int statusCode;
  _StatusHttpRequest(this.url, this.statusCode);

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<HttpClientResponse> close() async {
    final body = statusCode == 200
        ? jsonEncode({
            'docker': {
              'containers': {'total': 2, 'running': 1, 'stopped': 1},
              'images': 3,
            },
          })
        : (statusCode == 401
            ? '{"detail":"Invalid API Key or Admin Credentials"}'
            : 'server internal error');
    return _FakeHttpResponse(statusCode, body);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name] = [value.toString()];
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _values.forEach(action);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpResponse implements HttpClientResponse {
  final int _statusCode;
  final Uint8List _body;

  _FakeHttpResponse(int statusCode, String body)
      : _statusCode = statusCode,
        _body = Uint8List.fromList(utf8.encode(body));

  @override
  int get statusCode => _statusCode;

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  int get contentLength => _body.length;

  @override
  List<RedirectInfo> get redirects => <RedirectInfo>[];

  @override
  String get reasonPhrase => 'OK';

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<Uint8List>.value(_body).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
