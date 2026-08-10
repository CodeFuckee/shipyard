/// 备份与恢复相关数据模型。
library;

/// 单个备份文件信息。
class BackupItem {
  const BackupItem({
    required this.filename,
    required this.size,
    required this.createdAt,
  });

  /// 备份文件名（如 backup_20260801_120000.tar.gz.enc）。
  final String filename;

  /// 文件大小（字节）。
  final int size;

  /// 创建时间（YYYYMMDDHHMMSS 格式，来自后端）。
  final String createdAt;

  factory BackupItem.fromJson(Map<String, dynamic> json) {
    return BackupItem(
      filename: json['filename'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

/// 定时备份调度配置。
class BackupSchedule {
  const BackupSchedule({
    required this.enabled,
    required this.cron,
    required this.keepDays,
    this.nextFire,
  });

  /// 是否启用定时备份。
  final bool enabled;

  /// cron 表达式（5 段），未启用时可能为空字符串。
  final String cron;

  /// 自动清理保留天数。
  final int keepDays;

  /// 下次触发时间（YYYYMMDDHHMMSS 格式），未启用时为 null。
  final String? nextFire;

  factory BackupSchedule.fromJson(Map<String, dynamic> json) {
    return BackupSchedule(
      enabled: json['enabled'] as bool? ?? false,
      cron: json['cron'] as String? ?? '',
      keepDays: (json['keep_days'] as num?)?.toInt() ?? 30,
      nextFire: json['next_fire'] as String?,
    );
  }
}
