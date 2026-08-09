import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/projects_screen.dart';
import 'test_utils.dart';

/// 创建项目对话框的 Git 仓库 URL（git clone 创建）功能测试。
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

  Future<void> openCreateDialog(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
  }

  testWidgets('创建项目对话框应显示 Git 仓库 URL 输入框', (tester) async {
    await pumpProjectsScreen(tester);
    await openCreateDialog(tester);

    // 对话框应包含 Git Repository URL 输入框（名称/描述/Git URL 共 3 个字段）
    expect(find.text('Git Repository URL'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));
  });

  testWidgets('填写 Git 仓库 URL 创建项目时请求体应包含 git_url', (tester) async {
    await pumpProjectsScreen(tester);
    await openCreateDialog(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'myapp');
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'https://example.com/user/myapp.git',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create Project'));
    await tester.pumpAndSettle();

    // 找到 POST /projects 请求并验证请求体
    final post = captured.firstWhere(
      (r) => r.method == 'POST' && r.url.path == '/projects',
    );
    final body = json.decode(post.body) as Map<String, dynamic>;
    expect(body['name'], 'myapp');
    expect(body['git_url'], 'https://example.com/user/myapp.git');
  });

  testWidgets('不填 Git 仓库 URL 时请求体不应包含 git_url', (tester) async {
    await pumpProjectsScreen(tester);
    await openCreateDialog(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'plainapp');
    await tester.tap(find.widgetWithText(FilledButton, 'Create Project'));
    await tester.pumpAndSettle();

    final post = captured.firstWhere(
      (r) => r.method == 'POST' && r.url.path == '/projects',
    );
    final body = json.decode(post.body) as Map<String, dynamic>;
    expect(body['name'], 'plainapp');
    expect(body.containsKey('git_url'), isFalse);
  });

  testWidgets('Git 仓库 URL 为空白时请求体不应包含 git_url', (tester) async {
    await pumpProjectsScreen(tester);
    await openCreateDialog(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'blankapp');
    await tester.enterText(find.byType(TextFormField).at(2), '   ');
    await tester.tap(find.widgetWithText(FilledButton, 'Create Project'));
    await tester.pumpAndSettle();

    final post = captured.firstWhere(
      (r) => r.method == 'POST' && r.url.path == '/projects',
    );
    final body = json.decode(post.body) as Map<String, dynamic>;
    expect(body.containsKey('git_url'), isFalse);
  });
}

/// 捕获的 HTTP 请求记录。
class _CapturedRequest {
  _CapturedRequest(this.method, this.url, this.body);
  final String method;
  final Uri url;
  final String body;
}

/// 拦截 HTTP 并记录请求的 Fake 栈：GET 返回空列表，POST 返回创建成功。
class _FakeHttpOverrides extends HttpOverrides {
  _FakeHttpOverrides(this.captured);
  final List<_CapturedRequest> captured;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(captured);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.captured);
  final List<_CapturedRequest> captured;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeHttpRequest('GET', url, captured);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeHttpRequest(method, url, captured);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpRequest implements HttpClientRequest {
  _FakeHttpRequest(this.method, this.url, this.captured);
  @override
  final String method;
  final Uri url;
  final List<_CapturedRequest> captured;
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
    // GET 返回空项目列表；POST 返回创建成功（201）
    if (method == 'POST') {
      return _FakeHttpResponse(201, '{"id":"proj_test","name":"t"}');
    }
    return _FakeHttpResponse(200, '[]');
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
