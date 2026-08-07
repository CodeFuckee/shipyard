import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/services/auth_service.dart';

/// AuthService 登录态 token 有效性验证测试。
///
/// 背景：AuthGate 之前只检查 localStorage 中 token 是否存在，不验证
/// 有效性。浏览器残留过期/被删除/其他实例的 API Key 时直接进入概览页，
/// 所有请求 401，页面直接显示 "Invalid API Key or Admin Credentials"。
/// 修复后 isLoggedIn() 通过轻量请求（GET /admin/servers）验证 token，
/// 无效时自动清除凭据回登录页。
///
/// VM 测试环境中 PlatformDetector.isWeb 恒为 false，通过
/// AuthService.debugForceWeb = true 强制走 Web 分支，配合
/// debugHttpClient 注入 MockClient 验证请求行为。
void main() {
  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
    AuthService.debugHttpClient = null;
    AuthService.debugForceWeb = null;
  });

  test('token 存在且有效（200）时视为已登录', () async {
    SharedPreferences.setMockInitialValues({
      'docker_auth_server_url': 'https://home.chenkaidi.top:507',
      'docker_auth_token': 'valid-token',
    });

    AuthService.debugForceWeb = true;
    AuthService.debugHttpClient = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/admin/servers');
      expect(request.headers['x-api-key'], 'valid-token');
      expect(request.headers['Authorization'], 'Bearer valid-token');
      return http.Response('[]', 200);
    });

    expect(await AuthService.isLoggedIn(), isTrue);
  });

  test('token 无效（401）时视为未登录并清除凭据', () async {
    SharedPreferences.setMockInitialValues({
      'docker_auth_server_url': 'https://home.chenkaidi.top:508',
      'docker_auth_token': 'stale-invalid-token',
      'docker_api_key': 'stale-invalid-token',
      'docker_api_url': 'https://home.chenkaidi.top:508',
      'web_backend_url': 'https://home.chenkaidi.top:508',
      'web_backend_token': 'stale-invalid-token',
    });

    AuthService.debugForceWeb = true;
    AuthService.debugHttpClient = MockClient(
      (request) async => http.Response('{"detail":"Invalid API Key or Admin Credentials"}', 401),
    );

    expect(await AuthService.isLoggedIn(), isFalse);

    // 无效凭据应被清除，避免残留 token 反复触发 401
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('docker_auth_token'), isNull);
    expect(prefs.getString('docker_auth_server_url'), isNull);
    expect(prefs.getString('docker_api_key'), isNull);
    expect(prefs.getString('docker_api_url'), isNull);
    expect(prefs.getString('web_backend_url'), isNull);
    expect(prefs.getString('web_backend_token'), isNull);
  });

  test('403 同样视为未登录并清除凭据', () async {
    SharedPreferences.setMockInitialValues({
      'docker_auth_server_url': 'https://home.chenkaidi.top:507',
      'docker_auth_token': 'forbidden-token',
    });

    AuthService.debugForceWeb = true;
    AuthService.debugHttpClient =
        MockClient((request) async => http.Response('{}', 403));

    expect(await AuthService.isLoggedIn(), isFalse);
  });

  test('无 token 时不发起请求，直接未登录', () async {
    SharedPreferences.setMockInitialValues({});

    var requested = false;
    AuthService.debugForceWeb = true;
    AuthService.debugHttpClient = MockClient((request) async {
      requested = true;
      return http.Response('[]', 200);
    });

    expect(await AuthService.isLoggedIn(), isFalse);
    expect(requested, isFalse, reason: '无 token 时不应发起验证请求');
  });

  test('网络异常时保守视为已登录（不误杀临时网络故障）', () async {
    SharedPreferences.setMockInitialValues({
      'docker_auth_server_url': 'https://home.chenkaidi.top:507',
      'docker_auth_token': 'token',
    });

    AuthService.debugForceWeb = true;
    AuthService.debugHttpClient = MockClient(
      (request) async => throw http.ClientException('network down'),
    );

    expect(await AuthService.isLoggedIn(), isTrue);
  });

  test('验证请求超时视为已登录', () async {
    SharedPreferences.setMockInitialValues({
      'docker_auth_server_url': 'https://home.chenkaidi.top:507',
      'docker_auth_token': 'token',
    });

    AuthService.debugForceWeb = true;
    AuthService.debugHttpClient = MockClient((request) async {
      await Future.delayed(const Duration(milliseconds: 500));
      return http.Response('[]', 200);
    });

    expect(
      await AuthService.isLoggedIn(timeout: const Duration(milliseconds: 100)),
      isTrue,
    );
  });
}
