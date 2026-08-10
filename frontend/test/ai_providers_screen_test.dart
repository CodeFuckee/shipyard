import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/ai_providers_screen.dart';

import 'test_utils.dart';

/// AI 供应商配置页测试：列表渲染、添加/编辑/删除、测试连接、表单校验。
///
/// 通过 HttpOverrides 拦截真实 HTTP，Fake 服务器内存维护供应商列表。
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

  Future<void> pumpScreen(WidgetTester tester, {FakeAiProviderServer? server}) async {
    HttpOverrides.global = server ?? FakeAiProviderServer(captured);
    await tester.pumpWidget(buildTestApp(
      locale: const Locale('zh'),
      home: const AiProvidersScreen(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// 打开第一个供应商的操作菜单（非手机端弹出居中 AlertDialog 菜单）。
  Future<void> openFirstActions(WidgetTester tester) async {
    await tester.tap(find.byIcon(RemixIcon.more2Line).first);
    await tester.pumpAndSettle();
  }

  group('页面渲染', () {
    testWidgets('显示标题与供应商列表', (tester) async {
      await pumpScreen(tester);

      expect(find.text('AI 供应商配置'), findsOneWidget);
      expect(find.text('deepseek'), findsOneWidget);
      expect(find.text('https://api.deepseek.com'), findsOneWidget);
      expect(find.text('openai'), findsOneWidget);
      // 类型徽章
      expect(find.text('DeepSeek'), findsOneWidget);
      expect(find.text('OpenAI'), findsOneWidget);
      // Key 配置状态
      expect(find.text('已配置'), findsNWidgets(2));
    });

    testWidgets('未配置 Key 的供应商显示未配置', (tester) async {
      await pumpScreen(
        tester,
        server: FakeAiProviderServer(captured, noKeyProvider: true),
      );

      expect(find.text('未配置'), findsOneWidget);
    });

    testWidgets('空列表显示空提示', (tester) async {
      await pumpScreen(
        tester,
        server: FakeAiProviderServer(captured, emptyList: true),
      );

      expect(find.textContaining('暂无供应商'), findsOneWidget);
      // 空态上的添加按钮可点击
      expect(find.text('添加供应商'), findsOneWidget);
    });

    testWidgets('列表加载失败显示错误视图', (tester) async {
      await pumpScreen(
        tester,
        server: FakeAiProviderServer(captured, failList: true),
      );

      expect(find.text('重试'), findsOneWidget);
    });
  });

  group('添加供应商', () {
    testWidgets('FAB 打开表单，空名称不能保存', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('添加供应商'), findsWidgets);

      // 清空名称直接点保存 → 校验失败，不发出请求
      await tester.enterText(
        find.byKey(const ValueKey('ai-provider-name-field')),
        '',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pump();

      expect(find.text('请输入供应商名称'), findsOneWidget);
      expect(captured.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('非法 Base URL 不能保存', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('ai-provider-base-url-field')),
        'not-a-url',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pump();

      expect(find.textContaining('http(s)://'), findsOneWidget);
      expect(captured.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('填写表单保存 → 发送 POST 并刷新列表', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('ai-provider-name-field')),
        'qwen',
      );
      await tester.enterText(
        find.byKey(const ValueKey('ai-provider-base-url-field')),
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('ai-provider-api-key-field')),
        'sk-qwen-1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('ai-provider-model-field')),
        'qwen-max',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // POST 请求体校验
      final post = captured.firstWhere(
        (r) => r.method == 'POST' && r.url.path == '/admin/ai-providers',
      );
      final body = json.decode(post.body) as Map<String, dynamic>;
      expect(body['name'], 'qwen');
      expect(body['base_url'], 'https://dashscope.aliyuncs.com/compatible-mode/v1');
      expect(body['api_key'], 'sk-qwen-1');
      expect(body['provider_type'], 'deepseek');

      // 列表刷新出现新供应商
      expect(find.text('qwen'), findsOneWidget);
    });

    testWidgets('创建时选择 openai 预设自动填充 Base URL 与模型', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // 点开类型下拉框（当前值 DeepSeek，限定在对话框内避免与列表徽章歧义）
      await tester.tap(
        find.descendant(
          of: find.byType(DropdownButtonFormField<String>),
          matching: find.text('DeepSeek'),
        ),
      );
      await tester.pumpAndSettle();
      // 在弹出菜单中选择 OpenAI（列表页徽章也在 overlay 之外，用 .last 取菜单项）
      await tester.tap(find.text('OpenAI').last);
      await tester.pumpAndSettle();

      final baseUrlField = tester.widget<TextFormField>(
        find.byKey(const ValueKey('ai-provider-base-url-field')),
      );
      expect(baseUrlField.controller!.text, 'https://api.openai.com/v1');

      final modelField = tester.widget<TextFormField>(
        find.byKey(const ValueKey('ai-provider-model-field')),
      );
      expect(modelField.controller!.text, 'gpt-4o-mini');
    });
  });

  group('编辑供应商', () {
    testWidgets('编辑表单预填已有值，保存发送 PUT 且 Key 留空不发送', (tester) async {
      await pumpScreen(tester);
      await openFirstActions(tester);

      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();

      // 预填：deepseek 名称与 base_url 已在表单中
      final nameField = tester.widget<TextFormField>(
        find.byKey(const ValueKey('ai-provider-name-field')),
      );
      expect(nameField.controller!.text, 'deepseek');

      // 修改名称后保存
      await tester.enterText(
        find.byKey(const ValueKey('ai-provider-name-field')),
        'deepseek-v2',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final put = captured.firstWhere(
        (r) => r.method == 'PUT' && r.url.path.contains('/admin/ai-providers/'),
      );
      final body = json.decode(put.body) as Map<String, dynamic>;
      expect(body['name'], 'deepseek-v2');
      // Key 留空 → 不携带 api_key 字段
      expect(body.containsKey('api_key'), isFalse);
      expect(find.text('deepseek-v2'), findsOneWidget);
    });

    testWidgets('编辑时输入新 Key 会携带 api_key', (tester) async {
      await pumpScreen(tester);
      await openFirstActions(tester);

      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('ai-provider-api-key-field')),
        'sk-new-key',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final put = captured.firstWhere(
        (r) => r.method == 'PUT' && r.url.path.contains('/admin/ai-providers/'),
      );
      final body = json.decode(put.body) as Map<String, dynamic>;
      expect(body['api_key'], 'sk-new-key');
    });
  });

  group('删除供应商', () {
    testWidgets('确认删除发送 DELETE 并刷新列表', (tester) async {
      await pumpScreen(tester);
      await openFirstActions(tester);

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('确定删除该供应商？'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final del = captured.firstWhere(
        (r) => r.method == 'DELETE' &&
            r.url.path == '/admin/ai-providers/provider-deepseek',
      );
      expect(del.url.path, '/admin/ai-providers/provider-deepseek');
      expect(find.text('deepseek'), findsNothing);
    });

    testWidgets('取消删除不发送请求', (tester) async {
      await pumpScreen(tester);
      await openFirstActions(tester);

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();

      expect(captured.where((r) => r.method == 'DELETE'), isEmpty);
      expect(find.text('deepseek'), findsOneWidget);
    });
  });

  group('测试连接', () {
    testWidgets('测试连接成功提示连接成功并发送 POST /test', (tester) async {
      await pumpScreen(tester);
      await openFirstActions(tester);

      await tester.tap(find.text('测试连接'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final test = captured.firstWhere(
        (r) => r.method == 'POST' &&
            r.url.path == '/admin/ai-providers/provider-deepseek/test',
      );
      expect(test.url.path, '/admin/ai-providers/provider-deepseek/test');
      expect(find.text('连接成功'), findsOneWidget);
    });

    testWidgets('测试连接失败提示失败原因', (tester) async {
      await pumpScreen(
        tester,
        server: FakeAiProviderServer(captured, failTest: true),
      );
      await openFirstActions(tester);

      await tester.tap(find.text('测试连接'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('连接失败'), findsOneWidget);
      expect(find.textContaining('401'), findsOneWidget);
    });
  });
}

class _CapturedRequest {
  final String method;
  final Uri url;
  final String body;

  _CapturedRequest(this.method, this.url, this.body);
}

class FakeAiProviderServer extends HttpOverrides {
  FakeAiProviderServer(
    this.captured, {
    this.emptyList = false,
    this.failList = false,
    this.failTest = false,
    this.noKeyProvider = false,
  });

  final List<_CapturedRequest> captured;
  final bool emptyList;
  final bool failList;
  final bool failTest;
  final bool noKeyProvider;

  /// 模拟服务器上的供应商列表，跨请求共享状态。
  final List<Map<String, dynamic>> _providers = [
    {
      'id': 'provider-deepseek',
      'name': 'deepseek',
      'provider_type': 'deepseek',
      'base_url': 'https://api.deepseek.com',
      'default_model': 'deepseek-chat',
      'enabled': true,
      'api_key_configured': true,
      'created_at': '2026-08-01T00:00:00',
      'updated_at': '2026-08-01T00:00:00',
    },
    {
      'id': 'provider-openai',
      'name': 'openai',
      'provider_type': 'openai',
      'base_url': 'https://api.openai.com/v1',
      'default_model': 'gpt-4o-mini',
      'enabled': true,
      'api_key_configured': true,
      'created_at': '2026-08-01T00:00:00',
      'updated_at': '2026-08-01T00:00:00',
    },
  ];

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(captured, this);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.captured, this.server);
  final List<_CapturedRequest> captured;
  final FakeAiProviderServer server;

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
  final FakeAiProviderServer server;
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

    // 列表
    if (path == '/admin/ai-providers' && method == 'GET') {
      if (server.failList) {
        return _FakeHttpResponse(500, '{"detail":"boom"}');
      }
      if (server.noKeyProvider && server._providers.isNotEmpty) {
        server._providers[0]['api_key_configured'] = false;
      }
      return _FakeHttpResponse(
        200,
        json.encode(server.emptyList ? <dynamic>[] : server._providers),
      );
    }

    // 创建
    if (path == '/admin/ai-providers' && method == 'POST') {
      final body = json.decode(_body.toString()) as Map<String, dynamic>;
      final item = {
        'id': 'provider-${body['name']}',
        'name': body['name'],
        'provider_type': body['provider_type'],
        'base_url': body['base_url'],
        'default_model': body['default_model'] ?? '',
        'enabled': body['enabled'] ?? true,
        'api_key_configured': body['api_key'] != null && body['api_key'] != '',
      };
      server._providers.add(item);
      return _FakeHttpResponse(200, json.encode(item));
    }

    // 更新
    if (method == 'PUT' && path.startsWith('/admin/ai-providers/')) {
      final id = path.split('/').last;
      final body = json.decode(_body.toString()) as Map<String, dynamic>;
      final index = server._providers.indexWhere((p) => p['id'] == id);
      if (index == -1) return _FakeHttpResponse(404, '{"detail":"not found"}');
      final updated = {
        ...server._providers[index],
        if (body['name'] != null) 'name': body['name'],
        if (body['base_url'] != null) 'base_url': body['base_url'],
        if (body['provider_type'] != null) 'provider_type': body['provider_type'],
        if (body['default_model'] != null) 'default_model': body['default_model'],
        if (body['enabled'] != null) 'enabled': body['enabled'],
        if (body['api_key'] != null && body['api_key'] != '')
          'api_key_configured': true,
      };
      server._providers[index] = updated;
      return _FakeHttpResponse(200, json.encode(updated));
    }

    // 删除
    if (method == 'DELETE' && path.startsWith('/admin/ai-providers/')) {
      final id = path.split('/').last;
      server._providers.removeWhere((p) => p['id'] == id);
      return _FakeHttpResponse(200, '{"message":"deleted"}');
    }

    // 测试连接
    if (method == 'POST' && path.endsWith('/test')) {
      if (server.failTest) {
        return _FakeHttpResponse(200, '{"ok":false,"message":"API Key 无效或被拒绝（401）"}');
      }
      return _FakeHttpResponse(200, '{"ok":true,"message":"连接成功"}');
    }

    return _FakeHttpResponse(404, '{"detail":"not found"}');
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
