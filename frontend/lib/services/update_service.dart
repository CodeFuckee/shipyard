import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mobile_portainer_flutter_module/l10n/app_localizations.dart';
import 'package:mobile_portainer_flutter_module/utils/notify_utils.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import '../services/harmonyos_platform.dart';
import '../utils/platform_detector.dart';

class UpdateService {
  static const String _owner = 'CodeFuckee';
  static const String _repo = 'mobile_portainer_flutter_module';
  static const String _releasesUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  static Future<void> checkUpdate(BuildContext context,
      {bool showNoUpdateToast = false}) async {
    final t = AppLocalizations.of(context)!;
    try {
      final String currentVersion;
      if (PlatformDetector.isOhos) {
        final info = await HarmonyosPlatform.getPackageInfo();
        currentVersion = info['version'] as String;
      } else {
        final info = await PackageInfo.fromPlatform();
        currentVersion = info.version;
      }

      final response = await http.get(Uri.parse(_releasesUrl));
      if (response.statusCode == 200) {
        final Map<String, dynamic> release = json.decode(response.body);
        final String tagName = release['tag_name'] ?? '';
        // Remove 'v' prefix if present
        final String latestVersion = tagName.startsWith('v')
            ? tagName.substring(1).split('+')[0]
            : tagName.split('+')[0];

        if (_isNewVersion(currentVersion, latestVersion)) {
          final List<dynamic> assets = release['assets'] ?? [];
          String? downloadUrl;
          
          // Find APK asset
          for (var asset in assets) {
            if (asset['name'].toString().endsWith('.apk')) {
              downloadUrl = asset['browser_download_url'];
              break;
            }
          }

          if (downloadUrl != null && context.mounted) {
            _showUpdateDialog(
              context,
              latestVersion,
              release['body'] ?? '',
              downloadUrl,
            );
          }
        } else if (showNoUpdateToast && context.mounted) {
          NotifyUtils.showNotify(context, t.msgNoUpdate);
        }
      }
    } catch (e) {
      debugPrint('Error checking update: $e');
      if (showNoUpdateToast && context.mounted) {
        NotifyUtils.showNotify(context, t.errCheckUpdate);
      }
    }
  }

  static bool _isNewVersion(String current, String latest) {
    List<int> currentParts = current.split('.').map(int.parse).toList();
    List<int> latestParts = latest.split('.').map(int.parse).toList();

    for (int i = 0; i < latestParts.length; i++) {
      if (i >= currentParts.length) return true;
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  static void _showUpdateDialog(
      BuildContext context, String version, String description, String url) {
    final t = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${t.titleNewVersion} $version'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(description),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t.actionCancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _downloadAndInstall(context, url);
            },
            child: Text(t.actionUpdate),
          ),
        ],
      ),
    );
  }

  static Future<void> _downloadAndInstall(
      BuildContext context, String url) async {
    final t = AppLocalizations.of(context)!;
    final uri = Uri.parse(url);
    NotifyUtils.showNotify(context, t.msgOpeningBrowserForDownload);

    try {
      bool launched;
      if (PlatformDetector.isOhos) {
        launched = await HarmonyosPlatform.launchUrl(uri.toString());
      } else {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched) {
          launched = await launchUrl(uri);
        }
      }

      if (!launched && context.mounted) {
        NotifyUtils.showNotify(context, t.errOpenDownloadUrl);
      }
    } catch (e) {
      debugPrint('Error launching update url: $e');
      if (context.mounted) {
        NotifyUtils.showNotify(context, t.errOpenDownloadUrl);
      }
    }
  }
}
