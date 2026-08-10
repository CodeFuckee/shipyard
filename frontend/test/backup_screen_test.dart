import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/screens/backup_screen.dart';
import 'test_utils.dart';

/// 备份与恢复页面测试：列表展示、创建备份、恢复（输入 RESTORE 确认）、
/// 删除、下载、定时备份配置（简单/高级模式）。
void main() {
  final captured = <_CapturedRequest>[];

  setUp(() {
    captured.clear();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  Future<void> pumpBackupScreen(WidgetTester tester) async {
    HttpOverrides.global = _FakeBackupServer(captured);
    await tester.pumpWidget(buildTestApp(home: const BackupScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// 点击第一个备份项的操作按钮（按图标）。
  Future<void> tapFirstItemIcon(WidgetTester tester, IconData icon) async {
    await tester.tap(find.byIcon(icon).first);
    await tester.pumpAndSettle();
  }

  group('页面渲染', () {
    testWidgets('应显示标题、调度卡片与备份列表', (tester) async {
      await pumpBackupScreen(tester);

      // AppBar 标题
      expect(find.text('Backup & Restore'), findsOneWidget);
      // 调度开关卡片
      expect(find.text('Enable scheduled backup'), findsOneWidget);
      // 备份列表（2 个）
      expect(
        find.text('backup_20260801_120000.tar.gz.enc'),
        findsOneWidget,
      );
      expect(
        find.text('backup_20260802_130000.tar.gz.enc'),
        findsOneWidget,
      );
      // 创建备份按钮
      expect(find.text('Create backup'), findsOneWidget);
    });

    testWidgets('备份项应显示大小与创建时间', (tester) async {
      await pumpBackupScreen(tester);

      expect(find.textContaining('1.2 KB'), findsOneWidget);
      expect(find.textContaining('2026-08-01'), findsOneWidget);
    });

    testWidgets('无备份时显示空提示', (tester) async {
      HttpOverrides.global = _FakeBackupServer(captured, emptyBackups: true);
      await tester.pumpWidget(buildTestApp(home: const BackupScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('No backups yet'), findsOneWidget);
    });

    testWidgets('列表加载失败显示错误视图', (tester) async {
      HttpOverrides.global =
          _FakeBackupServer(captured, failList: true);
      await tester.pumpWidget(buildTestApp(home: const BackupScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('创建备份', () {
    testWidgets('点击创建备份应发送 POST /backups 并刷新列表', (tester) async {
      await pumpBackupScreen(tester);

      await tester.tap(find.text('Create backup'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // 应发出 POST /backups
      final post = captured.firstWhere(
        (r) => r.method == 'POST' && r.url.path == '/backups',
      );
      expect(post.url.path, '/backups');

      // 列表刷新为 3 项（Fake 添加了新备份）
      expect(
        find.text('backup_20260803_140000.tar.gz.enc'),
        findsOneWidget,
      );
    });

    testWidgets('创建备份失败应提示错误且列表不变', (tester) async {
      final server = _FakeBackupServer(captured, failCreate: true);
      HttpOverrides.global = server;
      await tester.pumpWidget(buildTestApp(home: const BackupScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Create backup'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Failed to create backup'), findsOneWidget);
      expect(
        find.text('backup_20260803_140000.tar.gz.enc'),
        findsNothing,
      );
    });
  });

  group('恢复备份', () {
    testWidgets('点击恢复应弹出确认对话框且执行按钮初始禁用', (tester) async {
      await pumpBackupScreen(tester);
      await tapFirstItemIcon(tester, RemixIcon.historyLine);

      expect(find.byType(AlertDialog), findsOneWidget);
      // 警告文案提示覆盖数据库与重启
      expect(find.textContaining('overwrite the current database'), findsOneWidget);
      // 未输入 RESTORE 时按钮禁用
      final restoreBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Restore'),
      );
      expect(restoreBtn.enabled, isFalse);
    });

    testWidgets('输入错误文字时按钮仍禁用，输入 RESTORE 后可执行', (tester) async {
      await pumpBackupScreen(tester);
      await tapFirstItemIcon(tester, RemixIcon.historyLine);

      final input = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      // 小写 restore 不通过
      await tester.enterText(input, 'restore');
      await tester.pump();
      var restoreBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Restore'),
      );
      expect(restoreBtn.enabled, isFalse);

      // 精确 RESTORE 通过
      await tester.enterText(input, 'RESTORE');
      await tester.pump();
      restoreBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Restore'),
      );
      expect(restoreBtn.enabled, isTrue);
    });

    testWidgets('确认恢复应发送 POST restore 请求并提示重启', (tester) async {
      await pumpBackupScreen(tester);
      await tapFirstItemIcon(tester, RemixIcon.historyLine);

      final input = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(input, 'RESTORE');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 应发出 POST /backups/{filename}/restore?confirm=true
      final restore = captured.firstWhere(
        (r) => r.method == 'POST' &&
            r.url.path == '/backups/backup_20260801_120000.tar.gz.enc/restore',
      );
      expect(restore.url.queryParameters['confirm'], 'true');
      // 对话框关闭 + 提示服务重启
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Service is restarting'), findsOneWidget);
    });

    testWidgets('取消恢复不应发送请求', (tester) async {
      await pumpBackupScreen(tester);
      await tapFirstItemIcon(tester, RemixIcon.historyLine);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        captured.where((r) => r.method == 'POST' && r.url.path.contains('restore')),
        isEmpty,
      );
    });

    testWidgets('恢复失败应提示错误', (tester) async {
      HttpOverrides.global = _FakeBackupServer(captured, failRestore: true);
      await tester.pumpWidget(buildTestApp(home: const BackupScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tapFirstItemIcon(tester, RemixIcon.historyLine);
      final input = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(input, 'RESTORE');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Restore failed'), findsOneWidget);
    });
  });

  group('删除备份', () {
    testWidgets('确认删除应发送 DELETE 并刷新列表', (tester) async {
      await pumpBackupScreen(tester);
      await tapFirstItemIcon(tester, RemixIcon.deleteBinLine);

      expect(find.textContaining('Delete this backup?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final del = captured.firstWhere(
        (r) => r.method == 'DELETE' &&
            r.url.path == '/backups/backup_20260801_120000.tar.gz.enc',
      );
      expect(del.url.path, '/backups/backup_20260801_120000.tar.gz.enc');
      // 列表只剩 1 个
      expect(
        find.text('backup_20260801_120000.tar.gz.enc'),
        findsNothing,
      );
    });

    testWidgets('取消删除不应发送 DELETE', (tester) async {
      await pumpBackupScreen(tester);
      await tapFirstItemIcon(tester, RemixIcon.deleteBinLine);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(
        captured.where((r) => r.method == 'DELETE').toList(),
        isEmpty,
      );
    });

    testWidgets('删除失败应提示错误且列表不变', (tester) async {
      HttpOverrides.global = _FakeBackupServer(captured, failDelete: true);
      await tester.pumpWidget(buildTestApp(home: const BackupScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tapFirstItemIcon(tester, RemixIcon.deleteBinLine);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Failed to delete backup'), findsOneWidget);
      expect(
        find.text('backup_20260801_120000.tar.gz.enc'),
        findsOneWidget,
      );
    });
  });

  group('下载备份', () {
    testWidgets('点击下载应发送 GET download 请求', (tester) async {
      await pumpBackupScreen(tester);
      await tapFirstItemIcon(tester, RemixIcon.downloadLine);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final dl = captured.firstWhere(
        (r) => r.method == 'GET' &&
            r.url.path == '/backups/backup_20260801_120000.tar.gz.enc/download',
      );
      expect(dl.url.path, '/backups/backup_20260801_120000.tar.gz.enc/download');
    });
  });

  group('定时备份配置', () {
    testWidgets('初始为禁用状态，开关打开后显示时间与保存按钮', (tester) async {
      await pumpBackupScreen(tester);

      // 初始禁用：不显示时间行
      expect(find.text('Daily time'), findsNothing);

      // 打开开关
      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(find.text('Daily time'), findsOneWidget);
      expect(find.text('02:00'), findsOneWidget);
    });

    testWidgets('保存简单模式配置应发送 PUT 请求（生成 cron）', (tester) async {
      await pumpBackupScreen(tester);
      await tester.tap(find.byType(Switch));
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final put = captured.firstWhere(
        (r) => r.method == 'PUT' && r.url.path == '/backups/schedule',
      );
      final body = json.decode(put.body) as Map<String, dynamic>;
      expect(body['enabled'], isTrue);
      expect(body['cron'], '0 2 * * *');
      expect(body['keep_days'], 30);
      expect(find.text('Schedule saved'), findsOneWidget);
    });

    testWidgets('高级模式可编辑 cron 表达式并保存', (tester) async {
      await pumpBackupScreen(tester);
      await tester.tap(find.byType(Switch));
      await tester.pump();

      // 切换高级模式
      await tester.tap(find.text('Advanced mode'));
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('cron_field')),
        '15 9 * * 1',
      );
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final put = captured.firstWhere(
        (r) => r.method == 'PUT' && r.url.path == '/backups/schedule',
      );
      final body = json.decode(put.body) as Map<String, dynamic>;
      expect(body['enabled'], isTrue);
      expect(body['cron'], '15 9 * * 1');
      expect(body['keep_days'], 30);
    });

    testWidgets('高级模式可切回简单模式', (tester) async {
      await pumpBackupScreen(tester);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.text('Advanced mode'));
      await tester.pump();

      expect(find.text('Simple mode'), findsOneWidget);
      await tester.tap(find.text('Simple mode'));
      await tester.pump();

      expect(find.text('Daily time'), findsOneWidget);
      expect(find.text('Advanced mode'), findsOneWidget);
    });

    testWidgets('调度保存失败应提示错误', (tester) async {
      HttpOverrides.global = _FakeBackupServer(captured, failSchedule: true);
      await tester.pumpWidget(buildTestApp(home: const BackupScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Failed to save schedule'), findsOneWidget);
    });
  });
}

class _CapturedRequest {
  _CapturedRequest(this.method, this.url, this.body);
  final String method;
  final Uri url;
  final String body;
}

/// 有状态 Fake：模拟 /backups 与 /backups/schedule 全套接口。
class _FakeBackupServer extends HttpOverrides {
  _FakeBackupServer(
    this.captured, {
    this.emptyBackups = false,
    this.failList = false,
    this.failCreate = false,
    this.failSchedule = false,
    this.failRestore = false,
    this.failDelete = false,
  });
  final List<_CapturedRequest> captured;
  final bool emptyBackups;
  final bool failList;
  final bool failCreate;
  final bool failSchedule;
  final bool failRestore;
  final bool failDelete;

  /// 模拟服务器上的备份列表，跨请求共享状态。
  final List<Map<String, dynamic>> _backups = [
    {
      'filename': 'backup_20260801_120000.tar.gz.enc',
      'size': 1234,
      'created_at': '20260801120000',
    },
    {
      'filename': 'backup_20260802_130000.tar.gz.enc',
      'size': 2048,
      'created_at': '20260802130000',
    },
  ];

  /// 模拟定时配置，跨请求共享状态。
  Map<String, dynamic> _schedule = {
    'enabled': false,
    'cron': '',
    'keep_days': 30,
    'next_fire': null,
  };

  int _createdCount = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(captured, this);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.captured, this.server);
  final List<_CapturedRequest> captured;
  final _FakeBackupServer server;

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
  final _FakeBackupServer server;
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

    if (path == '/backups' && method == 'GET') {
      if (server.failList) {
        return _FakeHttpResponse(500, '{"detail":"boom"}');
      }
      return _FakeHttpResponse(
        200,
        json.encode(
          server.emptyBackups ? <dynamic>[] : server._backups,
        ),
      );
    }
    if (path == '/backups' && method == 'POST') {
      if (server.failCreate) {
        return _FakeHttpResponse(500, '{"detail":"create failed"}');
      }
      server._createdCount++;
      final item = {
        'filename': 'backup_20260803_140000.tar.gz.enc',
        'size': 512,
        'created_at': '20260803140000',
      };
      server._backups.insert(0, item);
      return _FakeHttpResponse(201, json.encode(item));
    }
    if (path == '/backups/schedule' && method == 'GET') {
      return _FakeHttpResponse(200, json.encode(server._schedule));
    }
    if (path == '/backups/schedule' && method == 'PUT') {
      if (server.failSchedule) {
        return _FakeHttpResponse(500, '{"detail":"save failed"}');
      }
      final body = json.decode(_body.toString()) as Map<String, dynamic>;
      server._schedule = {
        'enabled': body['enabled'],
        'cron': body['cron'],
        'keep_days': body['keep_days'],
        'next_fire': body['enabled'] == true ? '20260811020000' : null,
      };
      return _FakeHttpResponse(200, json.encode(server._schedule));
    }
    if (path.endsWith('/download') && method == 'GET') {
      return _FakeHttpResponse(200, 'fake-backup-bytes');
    }
    if (method == 'DELETE') {
      if (server.failDelete) {
        return _FakeHttpResponse(500, '{"detail":"delete failed"}');
      }
      final filename = path.split('/').last;
      server._backups.removeWhere((b) => b['filename'] == filename);
      return _FakeHttpResponse(200, '{"status":"deleted"}');
    }
    if (method == 'POST' && path.contains('/restore')) {
      if (server.failRestore) {
        return _FakeHttpResponse(500, '{"detail":"restore failed"}');
      }
      return _FakeHttpResponse(200, '{"restored":"ok"}');
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
