// 首帧加载优化复现测试：canvaskit.wasm（约 7MB）首次加载耗时 30 秒。
//
// 根因（分析结论）：
//   1. nginx.conf 的 gzip_types 缺少 application/wasm —— 7MB 的
//      canvaskit.wasm 未压缩原样传输（实测 gzip -9 后仅 ~2.8MB，-60%）；
//   2. web/index.html 没有 preload —— canvaskit.wasm 要等 main.dart.js
//      执行后才发起请求，关键路径串行（瀑布式加载）；
//   3. 首次访问无缓存，全部 7MB 需从网络下载。
//
// 修复方案（用户选定方案 D）：
//   - CI 构建切换 dart2wasm（--wasm）：skwasm.wasm 3.4MB 替代 7MB
//     canvaskit.wasm（老浏览器自动降级 dart2js+canvaskit）；
//   - nginx 对 wasm 开启 gzip（实时 + gzip_static 预压缩）；
//   - index.html 动态 preload 与 loader 决策一致的 wasm 文件。
//
// 这些测试断言部署配置中必须存在上述优化；修复前失败、修复后通过。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// 测试运行目录为 frontend/，源文件在 web/、nginx.conf、Dockerfile*，
// 仓库根在 ../（Dockerfile.cn / Dockerfile.gpu.cn / .gitlab-ci.yml）
const _webDir = 'web';
const _nginxConf = 'nginx.conf';
const _dockerfileWeb = 'Dockerfile.web';
const _dockerfileCn = '../Dockerfile.cn';
const _dockerfileGpuCn = '../Dockerfile.gpu.cn';
const _gitlabCi = '../.gitlab-ci.yml';

void main() {
  group('nginx 静态资源压缩配置', () {
    test('gzip_types 必须包含 application/wasm（否则 7MB wasm 未压缩传输）',
        () {
      final content = File(_nginxConf).readAsStringSync();
      // gzip_types 行必须列出 application/wasm
      final gzipLine =
          content.split('\n').firstWhere((l) => l.contains('gzip_types'));
      expect(
        gzipLine,
        contains('application/wasm'),
        reason: 'nginx.conf 的 gzip_types 缺少 application/wasm，'
            'canvaskit.wasm（7MB）将以未压缩形式传输，'
            '是国内网络下首次加载耗时 30 秒的根因之一',
      );
    });

    test('必须启用 gzip_static 以使用预压缩 .gz 产物', () {
      final content = File(_nginxConf).readAsStringSync();
      expect(
        content,
        contains('gzip_static on'),
        reason: '缺少 gzip_static on：Dockerfile 预压缩的 .gz 文件不会被'
            '使用，只能靠实时 gzip（默认压缩级别 1，压缩率低）',
      );
    });

    test('必须为 .mjs 声明 application/javascript MIME（否则 dart2wasm 白屏）',
        () {
      final content = File(_nginxConf).readAsStringSync();
      expect(
        content,
        contains('mjs'),
        reason: 'Debian nginx 的 mime.types 无 .mjs 条目（返回 '
            'application/octet-stream），浏览器对 module script 严格 MIME '
            '校验拒绝加载 main.dart.mjs，dart2wasm 应用白屏——CI 流水线 '
            '500 实测 selenium_tests_prod 40 分钟超时、页面 flutter-view '
            '永不出现',
      );
    });
  });

  group('web/index.html 关键路径优化', () {
    test('必须按 renderer 决策动态 preload wasm 使其与 main.dart.js 并行下载',
        () {
      final content = File('$_webDir/index.html').readAsStringSync();
      expect(
        content,
        contains('preload'),
        reason: 'index.html 缺少 <link rel="preload">：wasm 要等'
            'main.dart.js 执行后才开始下载，关键路径串行拉长',
      );
      expect(
        content,
        contains('skwasm.wasm'),
        reason: 'preload 决策必须覆盖 skwasm 路径（支持 WasmGC 的浏览器'
            '主路径）',
      );
      expect(
        content,
        contains('canvaskit.wasm'),
        reason: 'preload 决策必须覆盖 canvaskit 路径（老浏览器降级路径）',
      );
    });
  });

  group('部署镜像预压缩', () {
    test('Dockerfile.cn（主部署）必须预压缩 wasm/js 生成 .gz 文件', () {
      final content = File(_dockerfileCn).readAsStringSync();
      expect(
        content,
        contains('gzip'),
        reason: 'Dockerfile.cn 未预压缩 wasm/js：实时 gzip 级别低、CPU'
            '开销大；静态预压缩（gzip -k -9）体积更小且零运行时开销',
      );
    });

    test('Dockerfile.gpu.cn 必须同样预压缩', () {
      final content = File(_dockerfileGpuCn).readAsStringSync();
      expect(
        content,
        contains('gzip'),
        reason: 'Dockerfile.gpu.cn 与 Dockerfile.cn 部署同一套前端产物，'
            '必须同步预压缩',
      );
    });

    test('frontend/Dockerfile.web（备用）必须预压缩', () {
      final content = File(_dockerfileWeb).readAsStringSync();
      expect(
        content,
        contains('gzip'),
        reason: 'frontend/Dockerfile.web 未预压缩 canvaskit.wasm',
      );
    });
  });

  group('CI 构建（dart2wasm + skwasm）', () {
    test('frontend:build_web 必须使用 --wasm 构建（skwasm 替代 7MB canvaskit）',
        () {
      final content = File(_gitlabCi).readAsStringSync();
      expect(
        content,
        contains('flutter build web --wasm'),
        reason: 'CI 构建未启用 --wasm：仍只产出 dart2js + canvaskit（7MB'
            ' wasm），skwasm（3.4MB，-50%）方案未落地',
      );
    });

    test('CI 必须为 dart2wasm 提供 wasm-opt（binaryen）工具链', () {
      final content = File(_gitlabCi).readAsStringSync();
      expect(
        content,
        contains('wasm-opt'),
        reason: 'CI 的 ohos 分支 Flutter SDK 缺 wasm-opt（本地实测 dart2wasm'
            ' 编译报 "Could not find .../wasm-opt"），不安装 binaryen 则'
            ' --wasm 构建必失败',
      );
    });
  });
}
