import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_portainer_flutter_module/utils/mixed_content_check.dart';

/// isMixedContentTarget 边界测试:
/// 网页授权添加对话框中,https 源页面 + http 目标会被浏览器 mixed content
/// 规则阻止,需在输入 URL 时提前提示并禁用"继续"按钮。
void main() {
  group('isMixedContentTarget', () {
    // ---- 正常路径 ----
    test('https 源页面 + http 目标 → true', () {
      expect(
        isMixedContentTarget('http://10.0.0.122:8080', sourceIsHttps: true),
        isTrue,
      );
    });

    test('https 源页面 + http 目标(带端口与路径)→ true', () {
      expect(
        isMixedContentTarget(
          'http://192.168.1.10:8000/connect/authorize',
          sourceIsHttps: true,
        ),
        isTrue,
      );
    });

    // ---- 不应触发提示的情况 ----
    test('https 源页面 + https 目标 → false', () {
      expect(
        isMixedContentTarget(
          'https://home.chenkaidi.top:507',
          sourceIsHttps: true,
        ),
        isFalse,
      );
    });

    test('http 源页面 + http 目标 → false(mixed content 仅发生在 https 源)', () {
      expect(
        isMixedContentTarget('http://10.0.0.122:8080', sourceIsHttps: false),
        isFalse,
      );
    });

    test('http 源页面 + https 目标 → false', () {
      expect(
        isMixedContentTarget('https://home.chenkaidi.top:507', sourceIsHttps: false),
        isFalse,
      );
    });

    // ---- 边界:URL 形态 ----
    test('https 源页面 + 仅预填 http:// → true(对话框默认预填值)', () {
      expect(
        isMixedContentTarget('http://', sourceIsHttps: true),
        isTrue,
      );
    });

    test('https 源页面 + 无 scheme 的 IP:port → false(不误报未输完的地址)', () {
      expect(
        isMixedContentTarget('10.0.0.122:8080', sourceIsHttps: true),
        isFalse,
      );
    });

    test('https 源页面 + 裸主机名 → false', () {
      expect(
        isMixedContentTarget('home.chenkaidi.top', sourceIsHttps: true),
        isFalse,
      );
    });

    test('https 源页面 + 空输入 / 纯空白 → false', () {
      expect(isMixedContentTarget('', sourceIsHttps: true), isFalse);
      expect(isMixedContentTarget('   ', sourceIsHttps: true), isFalse);
    });

    test('https 源页面 + 其他 scheme(ftp:)→ false', () {
      expect(
        isMixedContentTarget('ftp://example.com', sourceIsHttps: true),
        isFalse,
      );
    });

    test('scheme 大小写不敏感:大写 HTTP:// 同样判定为 http 目标', () {
      expect(
        isMixedContentTarget('HTTP://10.0.0.122:8080', sourceIsHttps: true),
        isTrue,
      );
    });

    test('前后空白不影响判定', () {
      expect(
        isMixedContentTarget('  http://10.0.0.122:8080  ', sourceIsHttps: true),
        isTrue,
      );
    });
  });
}
