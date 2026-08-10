import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/services/connect_service.dart';

/// 移动端 /connect 流程测试(io 分支)。
///
/// 覆盖:探测、注册授权链接、回调交换 token 全流程与安全约束
/// (state 防 CSRF、授权码一次性、存储清理)。
void main() {
  tearDown(() {
    SharedPreferences.setMockInitialValues({});
    ConnectService.debugHttpClient = null;
  });

  group('probe 能力探测(io 分支)', () {
    test('返回 enabled=true 时支持', () async {
      ConnectService.debugHttpClient =
          MockClient((req) async => http.Response('{"enabled": true}', 200));
      expect(await ConnectService.probe('http://10.0.0.1:9000'), isTrue);
    });

    test('返回非 JSON(老版本 nginx SPA 回退)不支持', () async {
      ConnectService.debugHttpClient =
          MockClient((req) async => http.Response('<!DOCTYPE html>', 200));
      expect(await ConnectService.probe('http://10.0.0.1:9000'), isFalse);
    });

    test('HTTP 500 不支持', () async {
      ConnectService.debugHttpClient =
          MockClient((req) async => http.Response('Internal Error', 500));
      expect(await ConnectService.probe('http://10.0.0.1:9000'), isFalse);
    });

    test('请求异常(网络错误)不支持', () async {
      ConnectService.debugHttpClient =
          MockClient((req) async => throw http.ClientException('timeout'));
      expect(await ConnectService.probe('http://10.0.0.1:9000'), isFalse);
    });
  });

  group('buildAuthorizeUrl 注册流程', () {
    test('注册成功返回带 state/challenge 的授权页 URL', () async {
      SharedPreferences.setMockInitialValues({});
      ConnectService.debugHttpClient = MockClient((req) async {
        if (req.url.path.endsWith('/connect/register')) {
          expect(req.url.host, '10.0.0.1');
          final body = jsonDecode(req.body) as Map;
          expect(body['redirect_uri'], 'shipyard://connect/callback');
          expect(body['client_name'], isNotEmpty);
          return http.Response(
              jsonEncode({'client_id': 'client-123', 'client_name': 'x'}), 200);
        }
        return http.Response('not found', 404);
      });

      final url =
          await ConnectService.buildAuthorizeUrl('http://10.0.0.1:9000');
      final uri = Uri.parse(url);
      expect(uri.path, '/connect/authorize');
      expect(uri.queryParameters['client_id'], 'client-123');
      expect(uri.queryParameters['redirect_uri'], 'shipyard://connect/callback');
      expect(uri.queryParameters['state'], isNotNull);
      expect(uri.queryParameters['state'], isNotEmpty);
      expect(uri.queryParameters['code_challenge'], isNotEmpty);
    });

    test('注册失败(非 200)抛异常', () async {
      ConnectService.debugHttpClient =
          MockClient((req) async => http.Response('nope', 404));
      expect(
        () => ConnectService.buildAuthorizeUrl('http://10.0.0.1:9000'),
        throwsException,
      );
    });

    test('未返回 client_id 抛异常', () async {
      ConnectService.debugHttpClient =
          MockClient((req) async => http.Response('{"client_id": ""}', 200));
      expect(
        () => ConnectService.buildAuthorizeUrl('http://10.0.0.1:9000'),
        throwsException,
      );
    });
  });

  group('completeFlow 回调交换', () {
    test('完整流程:注册 → 回跳 → token 交换成功并清理状态', () async {
      SharedPreferences.setMockInitialValues({});
      var tokenCalled = false;
      ConnectService.debugHttpClient = MockClient((req) async {
        if (req.url.path.endsWith('/connect/register')) {
          return http.Response(
              jsonEncode({'client_id': 'client-123', 'client_name': 'x'}), 200);
        }
        if (req.url.path.endsWith('/connect/token')) {
          tokenCalled = true;
          final body = jsonDecode(req.body) as Map;
          expect(body['client_id'], 'client-123');
          expect(body['code'], 'auth-code-1');
          expect(body['code_verifier'], isNotEmpty);
          return http.Response(jsonEncode({'apikey': 'mobile-key-1'}), 200);
        }
        return http.Response('not found', 404);
      });

      // 发起授权,内部保存 state/verifier
      final authorizeUrl =
          await ConnectService.buildAuthorizeUrl('http://10.0.0.1:9000');
      final state =
          Uri.parse(authorizeUrl).queryParameters['state']!;

      // 模拟授权页回跳(带 code + state)
      final callback = Uri.parse(
          'shipyard://connect/callback?code=auth-code-1&state=$state');
      expect(ConnectService.isCallbackUri(callback), isTrue);

      final result = await ConnectService.completeFlow(callback);
      expect(result, isNotNull);
      expect(result!.serverUrl, 'http://10.0.0.1:9000');
      expect(result.apikey, 'mobile-key-1');
      expect(tokenCalled, isTrue);

      // 授权码一次性:交换成功后流程状态已清理,再次回跳无法重复交换
      final again = await ConnectService.completeFlow(callback);
      expect(again, isNull);
    });

    test('state 不匹配(CSRF 防护)返回 null', () async {
      SharedPreferences.setMockInitialValues({});
      ConnectService.debugHttpClient = MockClient((req) async {
        if (req.url.path.endsWith('/connect/register')) {
          return http.Response(
              jsonEncode({'client_id': 'client-123', 'client_name': 'x'}), 200);
        }
        return http.Response('not found', 404);
      });

      await ConnectService.buildAuthorizeUrl('http://10.0.0.1:9000');
      final callback = Uri.parse(
          'shipyard://connect/callback?code=hijacked&state=wrong-state');
      expect(await ConnectService.completeFlow(callback), isNull);
    });

    test('缺少 code/state 参数返回 null', () async {
      expect(
        await ConnectService.completeFlow(
            Uri.parse('shipyard://connect/callback')),
        isNull,
      );
      expect(
        await ConnectService.completeFlow(
            Uri.parse('shipyard://connect/callback?code=only')),
        isNull,
      );
    });

    test('token 交换失败(500)抛异常且清理状态', () async {
      SharedPreferences.setMockInitialValues({});
      ConnectService.debugHttpClient = MockClient((req) async {
        if (req.url.path.endsWith('/connect/register')) {
          return http.Response(
              jsonEncode({'client_id': 'client-123', 'client_name': 'x'}), 200);
        }
        if (req.url.path.endsWith('/connect/token')) {
          return http.Response('server error', 500);
        }
        return http.Response('not found', 404);
      });

      final authorizeUrl =
          await ConnectService.buildAuthorizeUrl('http://10.0.0.1:9000');
      final state = Uri.parse(authorizeUrl).queryParameters['state']!;
      final callback = Uri.parse(
          'shipyard://connect/callback?code=bad&state=$state');
      await expectLater(
        ConnectService.completeFlow(callback),
        throwsException,
      );
      // 失败后状态已清理,用户可重新发起
      expect(
        await ConnectService.completeFlow(callback),
        isNull,
      );
    });

    test('回跳 URL 不带 state 时 isCallbackUri 返回 false', () {
      expect(
        ConnectService.isCallbackUri(
            Uri.parse('shipyard://connect/callback?code=x')),
        isFalse,
      );
      expect(
        ConnectService.isCallbackUri(Uri.parse('shipyard://connect/callback')),
        isFalse,
      );
    });
  });
}
