import 'dart:js_interop';
import 'dart:typed_data';
import 'package:share_plus/share_plus.dart';

/// JS Blob 构造函数映射
extension type _JSBlob._(JSObject _) implements JSObject {
  external _JSBlob(JSArray<JSUint8Array> parts);
}

/// JS URL 静态方法
@JS('URL.createObjectURL')
external JSString _createObjectURL(JSAny blob);

@JS('URL.revokeObjectURL')
external void _revokeObjectURL(JSString url);

/// JS document 全局对象
extension type _JSDocument(JSObject _) implements JSObject {
  external JSObject createElement(JSString tagName);
}

/// JS HTML 元素
extension type _JSHTMLElement(JSObject _) implements JSObject {
  external void setAttribute(JSString qualifiedName, JSString value);
  external void click();
}

@JS('document')
external _JSDocument get _document;

class FileHelper {
  static Future<String> tempDirPath() async {
    return '/tmp';
  }

  static Future<String?> downloadDirPath() async {
    return null;
  }

  static Future<void> ensureDir(String path) async {}

  static Future<String> writeBytes(String path, Uint8List bytes) async {
    return path;
  }

  static Future<void> shareFile(String filePath, String name, {String? text}) async {
    await SharePlus.instance.share(ShareParams(
      text: text,
      title: text,
      files: [XFile(filePath)],
      subject: name,
    ));
  }

  static Future<void> shareBytes(Uint8List bytes, String name, {String? text}) async {
    await SharePlus.instance.share(ShareParams(
      text: text,
      title: text,
      files: [XFile.fromData(bytes, name: name, mimeType: 'application/octet-stream')],
      subject: name,
    ));
  }

  /// 触发浏览器下载文件
  static Future<void> triggerDownload(String name, Uint8List bytes) async {
    final jsArray = [bytes.toJS].toJS;
    final blob = _JSBlob(jsArray);
    final url = _createObjectURL(blob);
    final anchorJS = _document.createElement('a'.toJS);
    final anchor = _JSHTMLElement(anchorJS);
    anchor.setAttribute('href'.toJS, url);
    anchor.setAttribute('download'.toJS, name.toJS);
    anchor.click();
    _revokeObjectURL(url);
  }
}
