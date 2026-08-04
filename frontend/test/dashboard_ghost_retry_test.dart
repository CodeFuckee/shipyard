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
import 'package:mobile_portainer_flutter_module/services/server_list_storage.dart';
import 'test_utils.dart';

/// 复现测试：服务器从列表移除后，概览页仍持续拉取已移除服务器的数据（幽灵重试）。
///
/// 用户报告：服务器列表显示只有一个服务器，但页面一直拉取两个服务器的数据。
///
/// 根因：`_fetchServerData` 失败后设置 3 秒重试 Timer（无限重试）；而
/// `_loadData()`/`refresh()` 重建 `_serversData` 时从不取消旧服务器对象的
/// retryTimer（`dispose()` 只清理当前列表里的 Timer，且 IndexedStack 中
/// dashboard 常驻不销毁）。服务器被删除或列表刷新后，已移除的服务器仍被
/// 每 3 秒请求一次、永不停止——页面显示 1 个服务器，网络请求却是 2 个。
void main() {
  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
    ServerListStorage.debugHttpClient = null;
  });

  testWidgets('刷新后已移除的服务器不应再被重试拉取（幽灵重试）', (tester) async {
    // 窄窗口（<600）使概览页走单列 ListView，避免宽窗口 GridView
    // 多列导致服务器卡片内统计行渲染溢出
    tester.view.physicalSize = const Size(560, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // 登录服务器凭据（ServerListStorage forceWeb 读后端用）；
    // B 预置 dashboard 缓存（key 为 dashboard_cache_<url>）：失败走缓存
    // 分支（isUsingCache）不弹 toast，但 retryTimer 依然无条件设置，
    // 幽灵重试路径不受影响
    SharedPreferences.setMockInitialValues({
      'web_backend_url': 'http://127.0.0.1:9000',
      'web_backend_token': 'token-1',
      'dashboard_cache_http://127.0.0.1:2': jsonEncode({
        'totalContainers': 2,
        'runningContainers': 1,
        'stoppedContainers': 1,
        'totalImages': 3,
        'commitDateRaw': null,
        'usage': null,
        'timestamp': 0,
      }),
    });

    // DockerService 走真实 HttpClient（HttpOverrides 拦截并记录 /info 请求）
    final infoRequests = <String>[];
    HttpOverrides.global = _RecordingHttpOverrides(infoRequests);
    addTearDown(() {
      HttpOverrides.global = null;
    });

    // 后端 /admin/servers：首次返回 [A, B]，此后（模拟删除 B）只返回 [A]
    var listCalls = 0;
    ServerListStorage.debugHttpClient = MockClient((request) async {
      if (request.url.path != '/admin/servers') {
        return http.Response('not found', 404);
      }
      listCalls++;
      final servers = listCalls == 1
          ? [
              {'name': 'Server A', 'url': 'http://127.0.0.1:1', 'apiKey': 'key-a', 'ignoreSsl': 'false'},
              {'name': 'Server B', 'url': 'http://127.0.0.1:2', 'apiKey': 'key-b', 'ignoreSsl': 'false'},
            ]
          : [
              {'name': 'Server A', 'url': 'http://127.0.0.1:1', 'apiKey': 'key-a', 'ignoreSsl': 'false'},
            ];
      return http.Response(jsonEncode(servers), 200,
          headers: {'content-type': 'application/json'});
    });

    await tester.pumpWidget(buildTestApp(
      home: Scaffold(
        body: DashboardScreen(
          serverListStorageFactory: () => ServerListStorage(forceWeb: true),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    // 初始加载：A、B 各发起一次数据请求
    expect(infoRequests, contains('127.0.0.1:1'),
        reason: '列表中的服务器 A 应被拉取');
    expect(infoRequests, contains('127.0.0.1:2'),
        reason: '列表中的服务器 B 应被拉取');

    // B 拉取失败 → 3 秒后重试（列表中服务器的重试属正常行为）
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    final bRequestsBeforeRefresh =
        infoRequests.where((k) => k == '127.0.0.1:2').length;
    expect(bRequestsBeforeRefresh, greaterThanOrEqualTo(2),
        reason: '仍处于列表中的服务器失败后应重试');

    // 模拟用户在设置页删除服务器 B 后刷新概览页（列表只剩 A）
    tester
        .state<DashboardScreenState>(find.byType(DashboardScreen))
        .refresh();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // 刷新后列表只剩 1 个服务器（与用户报告的症状一致）
    expect(find.byType(Card), findsOneWidget,
        reason: '删除 B 后概览页应只显示 1 个服务器');

    // 关键断言：B 已不在列表中，之后不应再有任何对 B 的数据请求
    final bRequestsAfterRefresh =
        infoRequests.where((k) => k == '127.0.0.1:2').length;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(
      infoRequests.where((k) => k == '127.0.0.1:2').length,
      bRequestsAfterRefresh,
      reason: '已从列表移除的服务器不应再被重试拉取（幽灵请求）：'
          '_loadData 未取消旧 retryTimer，B 在刷新后仍每 3 秒被请求一次，'
          '页面显示 1 个服务器却一直拉取 2 个服务器的数据',
    );

    // 卸载 widget 触发 dispose 清理重试 Timer 与 toast Timer
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

/// 记录 /info 请求并返回差异化响应的 Fake HTTP 栈：
/// Server A（127.0.0.1:1）返回 200 正常数据，其余（Server B）返回 500。
class _RecordingHttpOverrides extends HttpOverrides {
  final List<String> infoRequests;
  _RecordingHttpOverrides(this.infoRequests);

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _RecordingHttpClient(infoRequests);
}

class _RecordingHttpClient implements HttpClient {
  final List<String> infoRequests;
  _RecordingHttpClient(this.infoRequests);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _RecordingHttpRequest(url, infoRequests);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _RecordingHttpRequest(url, infoRequests);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RecordingHttpRequest implements HttpClientRequest {
  final Uri url;
  final List<String> infoRequests;
  _RecordingHttpRequest(this.url, this.infoRequests);

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<HttpClientResponse> close() async {
    infoRequests.add('${url.host}:${url.port}');
    if (url.host == '127.0.0.1' && url.port == 1) {
      // Server A 正常
      return _FakeHttpResponse(
        200,
        jsonEncode({
          'docker': {
            'containers': {'total': 2, 'running': 1, 'stopped': 1},
            'images': 3,
          },
        }),
      );
    }
    // Server B 不可达（拉取失败 → 触发 3 秒重试）
    return _FakeHttpResponse(500, 'server error');
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
