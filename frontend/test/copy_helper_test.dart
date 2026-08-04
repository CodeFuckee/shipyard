import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_portainer_flutter_module/utils/copy_strategy.dart';

void main() {
  group('CopyStrategy 复制路径决策', () {
    test('HTTP 场景（navigator.clipboard 不可用）：走同步 execCommand 路径且不调用异步 API', () async {
      // 通过 HTTP 访问时浏览器 navigator.clipboard 为 null（非安全上下文），
      // 旧实现 Clipboard.setData 依赖该 API 导致剪贴板为空。
      // 修复后必须回退到同步 execCommand 写入。
      var apiCalls = 0;
      var execCalls = 0;
      final strategy = CopyStrategy(
        probeApi: () => false,
        writeViaApi: (text) async {
          apiCalls++;
          return true;
        },
        writeViaExecCommand: (text) {
          execCalls++;
          return true;
        },
      );

      final ok = await strategy.copy('sk-test-123');

      expect(ok, isTrue);
      expect(apiCalls, 0, reason: 'HTTP 下不得调用不可用的浏览器 clipboard API');
      expect(execCalls, 1, reason: '必须通过 execCommand 完成复制');
    });

    test('HTTPS 场景（clipboard API 可用）：优先走异步 API 路径', () async {
      var apiCalls = 0;
      var execCalls = 0;
      final strategy = CopyStrategy(
        probeApi: () => true,
        writeViaApi: (text) async {
          apiCalls++;
          return true;
        },
        writeViaExecCommand: (text) {
          execCalls++;
          return true;
        },
      );

      final ok = await strategy.copy('sk-test-456');

      expect(ok, isTrue);
      expect(apiCalls, 1);
      expect(execCalls, 0);
    });

    test('异步 API 写入失败：回退到同步 execCommand', () async {
      var apiCalls = 0;
      var execCalls = 0;
      final strategy = CopyStrategy(
        probeApi: () => true,
        writeViaApi: (text) async {
          apiCalls++;
          return false; // 浏览器拒绝写入（如权限被拒）
        },
        writeViaExecCommand: (text) {
          execCalls++;
          return true;
        },
      );

      final ok = await strategy.copy('sk-test-789');

      expect(ok, isTrue);
      expect(apiCalls, 1);
      expect(execCalls, 1, reason: 'API 失败时必须回退到 execCommand，不能静默失败');
    });

    test('execCommand 也失败：返回 false 告知调用方复制未完成', () async {
      final strategy = CopyStrategy(
        probeApi: () => false,
        writeViaApi: (text) async => true,
        writeViaExecCommand: (text) => false,
      );

      expect(await strategy.copy('sk-test-000'), isFalse);
    });

    test('execCommand 抛出 JS 异常（iOS Safari / 部分 WebView 回退路径报错）：copy() 必须返回 false 而非抛异常', () async {
      // 复现线上 bug：设置页面点击复制 API key 控制台报 Uncaught Error，
      // 剪贴板未写入。根因是 _writeTextViaExecCommand 中 textarea.select() /
      // document.execCommand('copy') 在部分浏览器环境同步抛 JS 异常，且该路径
      // 无 try/catch 保护，异常沿 async 链传播为未处理 Future error。
      final strategy = CopyStrategy(
        probeApi: () => false,
        writeViaApi: (text) async => true,
        writeViaExecCommand: (text) =>
            throw Exception('execCommand 在当前浏览器中不可用'),
      );

      final ok = await strategy.copy('sk-test-abc');

      expect(ok, isFalse, reason: '回退路径抛异常时不得向上传播，应视为复制失败');
    });

    test('异步 API 写入抛出异常：同样不得向调用方传播异常', () async {
      var execCalls = 0;
      final strategy = CopyStrategy(
        probeApi: () => true,
        writeViaApi: (text) async =>
            throw Exception('navigator.clipboard.writeText 被浏览器拒绝'),
        writeViaExecCommand: (text) {
          execCalls++;
          return true;
        },
      );

      final ok = await strategy.copy('sk-test-def');

      expect(ok, isTrue);
      expect(execCalls, 1, reason: 'API 抛异常时应回退到 execCommand 完成复制');
    });

    test('clipboard API 探测抛异常（HTTP 下 dart2js 编译 navigator.clipboard() 调用抛 TypeError）：copy() 不得抛异常，应回退 execCommand', () async {
      // 复现线上 bug：`@JS('navigator.clipboard')` 注解的函数被 dart2js 编译为
      // `navigator.clipboard()` 函数调用；HTTP 非安全上下文下该值为 undefined，
      // 调用 undefined() 抛 TypeError。probeApi 在 copy() 的 try/catch 之外，
      // 异常沿 async 链传播为 Uncaught Error，剪贴板未写入且无任何提示。
      var execCalls = 0;
      final strategy = CopyStrategy(
        probeApi: () =>
            throw Exception('TypeError: navigator.clipboard is not a function'),
        writeViaApi: (text) async => true,
        writeViaExecCommand: (text) {
          execCalls++;
          return true;
        },
      );

      final ok = await strategy.copy('sk-test-xyz');

      expect(ok, isTrue);
      expect(execCalls, 1, reason: '探测异常时视为 API 不可用，必须回退 execCommand');
    });
  });
}
