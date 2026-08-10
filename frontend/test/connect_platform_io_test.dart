import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/services/connect_platform.dart';
import 'package:mobile_portainer_flutter_module/services/connect_service.dart';
import 'package:mobile_portainer_flutter_module/services/platform/preferences_service.dart';

/// 移动端 /connect 平台能力测试(VM 环境解析为 io 实现)。
///
/// 覆盖 [ConnectPlatform] io 分支:
/// - SHA-256(纯 Dart crypto 包,与 Web 端 WebCrypto 输出一致)
/// - state/verifier 存储(SharedPreferences 往返)
/// - 跳转失败不抛异常(url_launcher 无平台通道时返回 false 而非崩溃)
/// - 深链消费(VM 无平台通道,返回 null)
void main() {
  // app_links 的 EventChannel 需要 binding 已初始化(纯 test 无 binding)
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ConnectPlatform.sha256Hex', () {
    test('空字符串 SHA-256 与标准值一致', () async {
      final hex = await ConnectPlatform.sha256Hex('');
      expect(hex, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    test('已知输入 SHA-256 与标准值一致(与 WebCrypto 输出互通)', () async {
      final hex = await ConnectPlatform.sha256Hex('abc');
      expect(hex, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });
  });

  group('ConnectPlatform 存储', () {
    test('storageSet/Get/Remove 往返', () async {
      SharedPreferences.setMockInitialValues({});
      await PreferencesService.getInstance();
      await ConnectPlatform.storageSet('connect_flow_test', 'hello');
      expect(await ConnectPlatform.storageGet('connect_flow_test'), 'hello');
      await ConnectPlatform.storageRemove('connect_flow_test');
      expect(await ConnectPlatform.storageGet('connect_flow_test'), isNull);
    });

    test('不存在的 key 返回 null', () async {
      SharedPreferences.setMockInitialValues({});
      await PreferencesService.getInstance();
      expect(await ConnectPlatform.storageGet('connect_flow_nonexist'), isNull);
    });
  });

  group('ConnectPlatform.redirect', () {
    test('无平台通道时不抛异常(返回 false,由调用方提示用户)', () async {
      // VM 中 url_launcher 无平台实现,MissingPluginException 应被吞掉
      final ok = await ConnectPlatform.redirect('http://127.0.0.1:8000/connect/authorize');
      expect(ok, isFalse);
    });
  });

  group('ConnectPlatform 深链', () {
    test('initialLink 在无深链时返回 null', () async {
      expect(await ConnectPlatform.initialLink(), isNull);
    });

    test('pendingLink 在无深链时返回 null', () async {
      expect(await ConnectPlatform.pendingLink(), isNull);
    });
  });

  group('ConnectService 移动端分支', () {
    test('buildRedirectUri 返回 shipyard:// 自定义 scheme', () {
      // VM 中 kIsWeb 恒 false,解析为移动端分支
      expect(ConnectService.buildRedirectUri(), 'shipyard://connect/callback');
    });
  });
}
