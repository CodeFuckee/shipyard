import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/harmonyos_platform.dart';
import 'platform_detector.dart';

class FileHelper {
  static Future<String> tempDirPath() async {
    if (PlatformDetector.isOhos) {
      return await HarmonyosPlatform.getTemporaryDirectory();
    }
    return (await getTemporaryDirectory()).path;
  }

  static Future<String?> downloadDirPath() async {
    if (PlatformDetector.isOhos) {
      return await HarmonyosPlatform.getDownloadsDirectory();
    }
    if (PlatformDetector.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download');
      if (await dir.exists()) return dir.path;
      final extDir = await getExternalStorageDirectory();
      return extDir?.path;
    }
    final dir = await getDownloadsDirectory();
    return dir?.path;
  }

  static Future<void> ensureDir(String path) async {
    await Directory(path).create(recursive: true);
  }

  static Future<String> writeBytes(String path, Uint8List bytes) async {
    final file = File(path);
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static Future<void> shareFile(String filePath, String name, {String? text}) async {
    if (PlatformDetector.isOhos) {
      await HarmonyosPlatform.shareFile(filePath, text: text ?? '');
      return;
    }
    await SharePlus.instance.share(ShareParams(
      text: text,
      files: [XFile(filePath)],
      subject: name,
    ));
  }

  static Future<void> triggerDownload(String name, Uint8List bytes) async {
    throw UnsupportedError('triggerDownload is only supported on web');
  }

  static Future<void> shareBytes(Uint8List bytes, String name, {String? text}) async {
    if (PlatformDetector.isOhos) {
      final tmpDir = await HarmonyosPlatform.getTemporaryDirectory();
      final filePath = '$tmpDir/$name';
      await writeBytes(filePath, bytes);
      await HarmonyosPlatform.shareFile(filePath, text: text ?? '');
      return;
    }
    await SharePlus.instance.share(ShareParams(
      text: text,
      title: text,
      files: [XFile.fromData(bytes, name: name, mimeType: 'application/octet-stream')],
      subject: name,
    ));
  }
}
