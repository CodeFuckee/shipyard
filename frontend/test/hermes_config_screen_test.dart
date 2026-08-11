import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/hermes_config_screen.dart';

import 'test_utils.dart';

/// Hermes 接入配置页测试：状态展示、编辑配置（保存/取消）、表单校验、API Key 留空。
///
/// 通过 HttpOverrides 拦截真实 HTTP，Fake 服务器内存维护配置状态。
void main() {
  final captured = <_CapturedRequest>[];

  setUp(() {
    captured.clear();
    SharedPreferences.setMockInitialValues({
      'docker_auth_server_url': 'https://home.chenkaidi.top:507',
      'docker_auth_token': 'token-1',
    });
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  Future<void> pumpScreen(WidgetTester tester, {FakeHermesServer? server}) async {
    HttpOverrides.global = server ?? FakeHermesServer(captured);
    await tester.pumpWidget(buildTestApp(
      locale: const Locale('zh'),
      home: const HermesConfigScreen(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('页面渲染', () {
    testWidgets('已启用状态：标题、实例地址、模型、Key 状态、来源', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Hermes 接入'), findsOneWidget);
      expect(find.text('已启用'), findsOneWidget);
      expect(find.text('https://hermes.example.com/v1'), findsOneWidget);
      expect(find.text('hermes-chat'), findsOneWidget);
      expect(find.text('已配置'), findsOneWidget);
      expect(find.text('环境变量'), findsOneWidget);
      expect(find.textContaining('连接成功'), findsOneWidget);
    });

    testWidgets('未配置状态：提示 + 测试结果失败', (tester) async {
      await pumpScreen(tester, server: FakeHermesServer(captured, disabled: true));

      expect(find.text('未配置'), findsNWidgets(2)); // 状态卡标题 + 信息卡 API Key 行
      expect(find.text('测试结果：未配置 HERMES_BASE_URL，Hermes 接入未启用'), findsOneWidget);
    });

    testWidgets('数据库来源：显示「前端设置」', (tester) async {
      await pumpScreen(tester, server: FakeHermesServer(captured, sourceDatabase: true));

      expect(find.text('前端设置'), findsOneWidget);
    });
  });

  group('编辑配置', () {
    testWidgets('点击编辑配置显示表单，保存后发送 PUT 并提示成功', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('编辑配置'));
      await tester.pumpAndSettle();

      // 表单出现：输入框 + 保存/取消按钮（信息卡可能滚出视口，label 只断言存在）
      expect(find.text('实例地址'), findsWidgets);
      expect(find.text('保存配置'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);

      // 修改实例地址并保存
      await tester.enterText(
        find.widgetWithText(TextFormField, '实例地址').last,
        'https://new.example.com/v1',
      );
      await tester.tap(find.text('保存配置'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // PUT 请求已发出且 body 正确
      expect(captured.where((r) => r.method == 'PUT' && r.url.path == '/admin/hermes/config').length, 1);
      final body = json.decode(
        captured.firstWhere((r) => r.method == 'PUT' && r.url.path == '/admin/hermes/config').body,
      ) as Map<String, dynamic>;
      expect(body['base_url'], 'https://new.example.com/v1');
      expect(body['api_key'], '');
      expect(body['model'], 'hermes-chat'); // 表单回填的当前模型值原样提交

      // 保存成功提示 + 表单关闭 + 状态刷新
      expect(find.text('配置已保存'), findsOneWidget);
      expect(find.text('保存配置'), findsNothing);
      expect(find.text('https://new.example.com/v1'), findsOneWidget);
      expect(find.text('前端设置'), findsOneWidget);
    });

    testWidgets('取消编辑：表单关闭且不发请求', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('编辑配置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('保存配置'), findsNothing);
      expect(captured.where((r) => r.method == 'PUT').length, 0);
    });

    testWidgets('非法 URL 校验：显示错误且不发请求', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('编辑配置'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, '实例地址').last,
        '不是合法地址',
      );
      await tester.tap(find.text('保存配置'));
      await tester.pumpAndSettle();

      expect(find.text('请输入合法的 http(s) 地址'), findsOneWidget);
      expect(captured.where((r) => r.method == 'PUT').length, 0);
    });

    testWidgets('API Key 已配置时提示留空保持不变', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('编辑配置'));
      await tester.pumpAndSettle();

      expect(find.text('留空表示不修改'), findsOneWidget);
    });

    testWidgets('保存失败显示错误提示', (tester) async {
      await pumpScreen(tester, server: FakeHermesServer(captured, failSave: true));

      await tester.tap(find.text('编辑配置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存配置'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('连接失败'), findsOneWidget);
    });
  });
}

class FakeHermesServer extends HttpOverrides {
  FakeHermesServer(
    this.captured, {
    this.disabled = false,
    this.sourceDatabase = false,
    this.failSave = false,
  });

  final List<_CapturedRequest> captured;
  final bool disabled;
  final bool sourceDatabase;
  final bool failSave;

  /// 模拟服务器上的配置状态，跨请求共享。
  final Map<String, dynamic> _status = {
    'enabled': true,
    'source': 'env',
    'base_url': 'https://hermes.example.com/v1',
    'model': 'hermes-chat',
    'api_key_configured': true,
    'test': {'ok': true, 'message': '连接成功'},
  };

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(captured, this);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.captured, this.server);
  final List<_CapturedRequest> captured;
  final FakeHermesServer server;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeHttpRequest('GET', url, captured, server);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeHttpRequest(method, url, captured, server);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpRequest implements HttpClientRequest {
  _FakeHttpRequest(this.method, this.url, this.captured, this.server);
  @override
  final String method;
  final Uri url;
  final List<_CapturedRequest> captured;
  final FakeHermesServer server;
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
    final path = url.path;

    // 状态查询
    if (path == '/admin/hermes/status' && method == 'GET') {
      if (server.sourceDatabase) {
        server._status['source'] = 'database';
      }
      if (server.disabled) {
        return _FakeHttpResponse(200, json.encode({
          'enabled': false,
          'source': 'env',
          'base_url': '',
          'model': '',
          'api_key_configured': false,
          'test': {'ok': false, 'message': '未配置 HERMES_BASE_URL，Hermes 接入未启用'},
        }));
      }
      return _FakeHttpResponse(200, json.encode(server._status));
    }

    // 保存配置
    if (path == '/admin/hermes/config' && method == 'PUT') {
      if (server.failSave) {
        return _FakeHttpResponse(500, '{"detail":"boom"}');
      }
      final body = json.decode(_body.toString()) as Map<String, dynamic>;
      final baseUrl = (body['base_url'] as String? ?? '').trim();
      server._status['base_url'] = baseUrl;
      server._status['model'] = body['model'] as String? ?? '';
      server._status['source'] = 'database';
      server._status['enabled'] = baseUrl.isNotEmpty;
      if ((body['api_key'] as String? ?? '').isNotEmpty) {
        server._status['api_key_configured'] = true;
      }
      server._status['test'] = {'ok': true, 'message': '连接成功'};
      return _FakeHttpResponse(200, json.encode(server._status));
    }

    return _FakeHttpResponse(404, '{"detail":"not found"}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpResponse implements HttpClientResponse {
  _FakeHttpResponse(this.statusCode, this.body) {
    // 声明 UTF-8，否则 http 包按 Latin-1 解码导致中文乱码
    headers.set('content-type', 'application/json; charset=utf-8');
  }
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
  String get reasonPhrase => statusCode == 200 ? 'OK' : 'Error';

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
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _values.putIfAbsent(name.toLowerCase(), () => []).add(value.toString());
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = [value.toString()];
  }

  @override
  ContentType? get contentType {
    final values = _values['content-type'];
    if (values == null || values.isEmpty) return null;
    return ContentType.parse(values.first);
  }

  @override
  String? value(String name) {
    final values = _values[name.toLowerCase()];
    return (values == null || values.isEmpty) ? null : values.first;
  }

  @override
  List<String>? operator [](String name) => _values[name.toLowerCase()];

  @override
  void forEach(void Function(String name, List<String> values) f) {
    _values.forEach(f);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CapturedRequest {
  final String method;
  final Uri url;
  final String body;

  _CapturedRequest(this.method, this.url, this.body);
}
