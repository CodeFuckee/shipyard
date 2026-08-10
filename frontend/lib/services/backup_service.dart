import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/backup.dart';
import 'platform/http_helper.dart';

/// 备份与恢复 API 客户端（对应后端 /backups 系列端点）。
///
/// 认证方式与 [DockerService] 一致：JWT Bearer token 或 X-API-Key。
class BackupService {
  BackupService({
    required this.baseUrl,
    this.apiKey,
    this.ignoreSsl = false,
  }) {
    _client = HttpHelper.createClient(ignoreSsl: ignoreSsl);
  }

  final String baseUrl;
  final String? apiKey;
  final bool ignoreSsl;
  late final http.Client _client;

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

  /// 从后端错误响应中提取友好错误消息；失败时回退通用描述。
  String _extractErrorMessage(String responseBody, String fallback) {
    try {
      final decoded = json.decode(responseBody);
      if (decoded is Map<String, dynamic>) {
        for (final key in ['detail', 'message', 'error', 'msg']) {
          final v = decoded[key];
          if (v is String && v.isNotEmpty) return v;
        }
      }
    } catch (_) {
      // 非 JSON 响应体，使用回退消息
    }
    return fallback;
  }

  Exception _error(http.Response resp, String fallback) {
    return Exception(_extractErrorMessage(
      utf8.decode(resp.bodyBytes),
      '$fallback (${resp.statusCode})',
    ));
  }

  Uri _uri(String path) => Uri.parse('$baseUrl/backups$path');

  /// 备份列表（按时间倒序）。
  Future<List<BackupItem>> listBackups() async {
    final resp = await _client.get(_uri(''), headers: _authHeaders());
    if (resp.statusCode != 200) {
      throw _error(resp, 'Failed to load backups');
    }
    final list = json.decode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
    return list
        .map((e) => BackupItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 手动创建一次备份。
  Future<BackupItem> createBackup() async {
    final resp = await _client.post(_uri(''), headers: _authHeaders());
    if (resp.statusCode != 201) {
      throw _error(resp, 'Failed to create backup');
    }
    return BackupItem.fromJson(
      json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// 删除指定备份。
  Future<void> deleteBackup(String filename) async {
    final resp = await _client.delete(
      _uri('/${Uri.encodeComponent(filename)}'),
      headers: _authHeaders(),
    );
    if (resp.statusCode != 200) {
      throw _error(resp, 'Failed to delete backup');
    }
  }

  /// 恢复指定备份（危险操作，覆盖数据库并触发服务重启）。
  Future<void> restoreBackup(String filename) async {
    final resp = await _client.post(
      _uri('/${Uri.encodeComponent(filename)}/restore?confirm=true'),
      headers: _authHeaders(),
    );
    if (resp.statusCode != 200) {
      throw _error(resp, 'Failed to restore backup');
    }
  }

  /// 下载备份文件（加密 tar.gz）的原始字节。
  Future<Uint8List> downloadBackup(String filename) async {
    final resp = await _client.get(
      _uri('/${Uri.encodeComponent(filename)}/download'),
      headers: _authHeaders(),
    );
    if (resp.statusCode != 200) {
      throw _error(resp, 'Failed to download backup');
    }
    return resp.bodyBytes;
  }

  /// 查询定时备份配置。
  Future<BackupSchedule> getSchedule() async {
    final resp = await _client.get(_uri('/schedule'), headers: _authHeaders());
    if (resp.statusCode != 200) {
      throw _error(resp, 'Failed to load schedule');
    }
    return BackupSchedule.fromJson(
      json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// 更新定时备份配置（后端立即生效）。
  Future<BackupSchedule> saveSchedule({
    required bool enabled,
    required String cron,
    required int keepDays,
  }) async {
    final resp = await _client.put(
      _uri('/schedule'),
      headers: _authHeaders({'Content-Type': 'application/json'}),
      body: json.encode({
        'enabled': enabled,
        'cron': cron,
        'keep_days': keepDays,
      }),
    );
    if (resp.statusCode != 200) {
      throw _error(resp, 'Failed to save schedule');
    }
    return BackupSchedule.fromJson(
      json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>,
    );
  }
}
