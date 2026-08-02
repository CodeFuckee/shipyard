import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/projects_screen.dart';
import 'package:mobile_portainer_flutter_module/theme/app_theme.dart';
import 'test_utils.dart';

/// 复现并验证 bug：
/// 项目页面的 FloatingActionButton 使用 `bottom: 16`，而容器页面
/// （main_tab_screen）使用 `AppTheme.fabBottomInset`（避开底部导航栏）。
/// 以容器页面为准，项目页面的 FAB 应与容器页面保持一致的底部偏移。
void main() {
  testWidgets('项目页面的 FAB 底部位置与容器页面保持一致', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({});

    // 让 /projects 请求返回 200 + 空列表，页面进入正常列表分支（渲染 FAB）
    HttpOverrides.global = _FakeHttpOverrides();
    addTearDown(() {
      HttpOverrides.global = null;
    });

    await tester.pumpWidget(buildTestApp(
      home: const Scaffold(body: ProjectListScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 找到 FAB
    final fabFinder = find.byType(FloatingActionButton);
    expect(fabFinder, findsOneWidget);

    // 获取 FAB 外层 Positioned 的 bottom 值
    final positionedFinder = find.ancestor(
      of: fabFinder,
      matching: find.byType(Positioned),
    );
    final positioned = tester.widget<Positioned>(positionedFinder);

    // 以容器页面为准：bottom 应为 AppTheme.fabBottomInset，而不是 16
    expect(positioned.bottom, AppTheme.fabBottomInset);
  });
}

/// 返回 200 空 JSON 数组的 Fake HTTP 栈，用于让 DockerService 请求成功。
class _FakeHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

class _FakeHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpRequest();

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeHttpRequest();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<HttpClientResponse> close() async => _FakeHttpResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpResponse implements HttpClientResponse {
  static final Uint8List _body = Uint8List.fromList(utf8.encode('[]'));

  @override
  int get statusCode => 200;

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
