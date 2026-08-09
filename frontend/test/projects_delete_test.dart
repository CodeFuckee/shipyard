import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/projects_screen.dart';
import 'test_utils.dart';

/// 项目列表删除功能测试：卡片右上角删除图标 → 确认对话框 → DELETE 请求。
void main() {
  final captured = <_CapturedRequest>[];

  setUp(() {
    captured.clear();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  Future<void> pumpProjectsScreen(WidgetTester tester) async {
    HttpOverrides.global = _FakeHttpOverrides(captured);
    await tester.pumpWidget(buildTestApp(
      home: const Scaffold(body: ProjectListScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// 点击第一个项目卡片的删除图标。
  Future<void> tapFirstDeleteIcon(WidgetTester tester) async {
    await tester.tap(find.byIcon(RemixIcon.deleteBinLine).first);
    await tester.pumpAndSettle();
  }

  testWidgets('每个项目卡片右上角应显示删除图标', (tester) async {
    await pumpProjectsScreen(tester);

    expect(find.byIcon(RemixIcon.deleteBinLine), findsNWidgets(2));
  });

  testWidgets('点击删除图标应弹出确认对话框', (tester) async {
    await pumpProjectsScreen(tester);
    await tapFirstDeleteIcon(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    // 确认文案应提示将同时删除关联文件
    expect(find.textContaining('All associated files'), findsOneWidget);
  });

  testWidgets('确认删除应发送 DELETE 请求并刷新列表', (tester) async {
    await pumpProjectsScreen(tester);
    await tapFirstDeleteIcon(tester);

    // 点击确认删除按钮
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    // 应发出 DELETE /projects/proj_1 请求
    final delete = captured.firstWhere(
      (r) => r.method == 'DELETE' && r.url.path == '/projects/proj_1',
    );
    expect(delete.url.path, '/projects/proj_1');

    // 删除成功后列表应刷新：只剩 1 个项目卡片
    expect(find.byIcon(RemixIcon.deleteBinLine), findsOneWidget);
  });

  testWidgets('取消删除不应发送 DELETE 请求', (tester) async {
    await pumpProjectsScreen(tester);
    await tapFirstDeleteIcon(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      captured.where((r) => r.method == 'DELETE').toList(),
      isEmpty,
    );
    // 列表保持 2 个项目
    expect(find.byIcon(RemixIcon.deleteBinLine), findsNWidgets(2));
  });

  testWidgets('长按项目卡片不应再触发删除对话框', (tester) async {
    await pumpProjectsScreen(tester);

    await tester.longPress(find.text('app-a'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      captured.where((r) => r.method == 'DELETE').toList(),
      isEmpty,
    );
  });
}

/// 捕获的 HTTP 请求记录。
class _CapturedRequest {
  _CapturedRequest(this.method, this.url, this.body);
  final String method;
  final Uri url;
  final String body;
}

/// 有状态 Fake：GET 返回当前项目列表，DELETE 从列表移除对应项目。
class _FakeHttpOverrides extends HttpOverrides {
  _FakeHttpOverrides(this.captured);
  final List<_CapturedRequest> captured;

  /// 模拟服务器上的项目列表（初始 2 个项目），跨请求共享状态。
  final List<Map<String, dynamic>> _projects = [
    {
      'id': 'proj_1',
      'name': 'app-a',
      'description': 'first app',
      'status': 'idle',
      'createdAt': '2026-01-01T00:00:00Z',
      'updatedAt': '2026-01-02T00:00:00Z',
    },
    {
      'id': 'proj_2',
      'name': 'app-b',
      'description': '',
      'status': 'running',
      'createdAt': '2026-01-01T00:00:00Z',
      'updatedAt': '2026-01-02T00:00:00Z',
    },
  ];

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(captured, _projects);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.captured, this._projects);
  final List<_CapturedRequest> captured;
  final List<Map<String, dynamic>> _projects;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeHttpRequest('GET', url, captured, _projects);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeHttpRequest(method, url, captured, _projects);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpRequest implements HttpClientRequest {
  _FakeHttpRequest(this.method, this.url, this.captured, this._projects);
  @override
  final String method;
  final Uri url;
  final List<_CapturedRequest> captured;
  final List<Map<String, dynamic>> _projects;
  final StringBuffer _body = StringBuffer();

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  void write(Object? object) => _body.write(object);

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {
    for (final o in objects) {
      _body.write(o);
    }
  }

  @override
  void add(List<int> data) => _body.write(utf8.decode(data));

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _body.write(utf8.decode(chunk));
    }
  }

  @override
  Future<HttpClientResponse> close() async {
    captured.add(_CapturedRequest(method, url, _body.toString()));
    // GET 返回项目列表；DELETE 移除项目并返回成功
    if (method == 'DELETE') {
      final path = url.path;
      final id = path.split('/').last;
      _projects.removeWhere((p) => p['id'] == id);
      return _FakeHttpResponse(200, '{"status":"deleted"}');
    }
    return _FakeHttpResponse(200, json.encode(_projects));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpResponse implements HttpClientResponse {
  _FakeHttpResponse(this.statusCode, this.body);
  @override
  final int statusCode;
  final String body;

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  int get contentLength => utf8.encode(body).length;

  @override
  List<RedirectInfo> get redirects => <RedirectInfo>[];

  @override
  String get reasonPhrase => statusCode == 201 ? 'Created' : 'OK';

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<Uint8List>.value(Uint8List.fromList(utf8.encode(body))).listen(
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
