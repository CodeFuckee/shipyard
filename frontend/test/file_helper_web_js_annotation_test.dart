import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Web 端下载失败 bug 的复现测试。
///
/// 现象：创建备份后点击下载，Web 端一直提示"下载失败"（后端下载接口
/// 200 OK）。真实浏览器运行时错误：`TypeError: p._JSBlob is not a
/// constructor`。
///
/// 根因：`lib/utils/file_helper_web.dart` 中 `_JSBlob` extension type
/// 的外部构造器缺少 `@JS('Blob')` 注解。dart:js_interop 的 extension
/// type 外部构造器在未注解时，dart2js 会编译为调用与 Dart 类型同名
/// （`_JSBlob`）的 JS 构造函数，而浏览器中只有全局 `Blob`——运行时
/// 必然抛 TypeError，`triggerDownload` 失败，被页面 catch 后提示
/// "下载失败"。
///
/// 注：dart:js_interop 仅在 Web 编译时可用，VM 测试无法直接调用
/// `triggerDownload`，因此用源码断言锚定编译期行为（缺失注解即编译
/// 产物必然错误，已在真实浏览器 + 本地后端复现验证）。
void main() {
  test('_JSBlob extension type 必须注解 @JS("Blob")', () {
    final source = File('lib/utils/file_helper_web.dart').readAsStringSync();

    // 定位 extension type _JSBlob 定义块（从定义处到下一个 extension type / class 或文件尾）
    final start = source.indexOf('extension type _JSBlob');
    expect(
      start,
      greaterThanOrEqualTo(0),
      reason: 'file_helper_web.dart 中应存在 _JSBlob extension type',
    );

    // 向上回溯查找其最近的前置注解（跳过空白与注释）
    final header = source.substring(0, start);
    final lastBrace = header.lastIndexOf('}');
    final prefix = header.substring(lastBrace + 1);
    expect(
      prefix.contains('@JS('),
      isTrue,
      reason: '_JSBlob 声明前应有 @JS(...) 注解（期望 @JS("Blob")）',
    );
    expect(
      prefix.contains("@JS('Blob')") || prefix.contains('@JS("Blob")'),
      isTrue,
      reason: '_JSBlob 必须注解为 @JS("Blob")，否则 dart2js 生成对 '
          'JS 中不存在的 _JSBlob 构造函数的调用，Web 端下载必失败',
    );
  });

  test('triggerDownload 使用带注解的 Blob 构造', () {
    final source = File('lib/utils/file_helper_web.dart').readAsStringSync();
    final fnStart = source.indexOf('static Future<void> triggerDownload');
    expect(fnStart, greaterThanOrEqualTo(0), reason: '存在 triggerDownload');

    final fnEnd = source.indexOf('}', fnStart);
    final fn = source.substring(fnStart, fnEnd + 1);
    expect(
      fn.contains('_JSBlob(') && fn.contains('_createObjectURL(blob)'),
      isTrue,
      reason: 'triggerDownload 应通过 _JSBlob 构造 Blob 并生成对象 URL',
    );
  });
}
