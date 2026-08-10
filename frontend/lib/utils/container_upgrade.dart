import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/docker_service.dart';
import 'notify_utils.dart';

/// 截断 digest 用于展示（sha256:64 位太长，显示前 16 字符）
String _shortDigest(String digest) {
  if (digest.length <= 16) return digest;
  return digest.substring(0, 16);
}

/// 显示一个不可关闭的 loading 对话框
void _showLoadingDialog(BuildContext context, String message) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      content: Row(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

/// 容器升级流程（容器列表页与详情页共用）：
/// 检查更新 → 展示结果 → 有更新时确认 → 执行升级 → 提示结果。
///
/// 注意：调用方需要自行创建 DockerService 实例传入。
Future<void> handleContainerUpgrade(
  BuildContext context,
  DockerService service,
  String containerId,
  String containerName,
) async {
  final t = AppLocalizations.of(context)!;

  // 1. 检查更新（后端会先拉取最新镜像再对比 digest）
  _showLoadingDialog(context, t.msgUpgradeChecking);
  Map<String, dynamic> checkResult;
  try {
    checkResult = await service.checkContainerUpdate(containerId);
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop(); // 关闭 loading
    NotifyUtils.showNotify(context, '${t.msgUpgradeFail}: $e');
    return;
  }
  if (!context.mounted) return;
  Navigator.of(context).pop(); // 关闭 loading

  final status = checkResult['status'] as String? ?? 'unknown';
  final currentImage = checkResult['current_image'] as String? ?? '';
  final currentDigest = checkResult['current_digest'] as String? ?? '';
  final latestDigest = checkResult['latest_digest'] as String? ?? '';

  // 已是最新版本：仅提示
  if (status == 'up_to_date') {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.msgUpgradeUpToDate),
        content: Text('$currentImage ${t.msgUpgradeUpToDate}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.actionConfirm),
          ),
        ],
      ),
    );
    return;
  }

  // 有更新 / 无法对比：展示确认框
  final String body;
  if (status == 'update_available') {
    body = '${t.msgUpgradeCurrent}: $currentImage\n'
        '${t.msgUpgradeLatest}: '
        '${_shortDigest(currentDigest)} → ${_shortDigest(latestDigest)}\n\n'
        '${t.msgUpgradeConfirmBody}';
  } else {
    // unknown：无法对比 digest，提示后仍允许尝试升级
    body = '${t.msgUpgradeUnknown}\n\n${t.msgUpgradeConfirmBody}';
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t.msgUpgradeConfirmTitle),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(t.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(t.actionConfirm),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  // 2. 执行升级
  _showLoadingDialog(context, t.msgUpgradeInProgress);
  try {
    await service.upgradeContainer(containerId);
    if (!context.mounted) return;
    Navigator.of(context).pop(); // 关闭 loading
    NotifyUtils.showNotify(context, '$containerName ${t.msgUpgradeSuccess}');
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop(); // 关闭 loading
    NotifyUtils.showNotify(context, '${t.msgUpgradeFail}: $e');
  }
}
