import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_portainer_flutter_module/services/oidc_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    SharedPreferences.setMockInitialValues({});
    OidcService.debugHttpClient = null;
  });

  test('仅保存有效的 HTTP(S) 服务器地址', () async {
    SharedPreferences.setMockInitialValues({});
    await OidcService.saveServerUrl('https://shipyard.example.test/');
    expect(await OidcService.savedServerUrl(), 'https://shipyard.example.test');
    expect(
      () => OidcService.saveServerUrl('shipyard://oidc/callback'),
      throwsA(isA<OidcException>()),
    );
  });

  test('未启用 OIDC 时不发起授权', () async {
    OidcService.debugHttpClient = MockClient(
      (_) async => http.Response('{"enabled": false}', 200),
    );

    expect(
      () => OidcService.buildAuthorizeUrl('https://shipyard.example.test'),
      throwsA(isA<OidcException>()),
    );
  });

  test('构造授权地址使用 PKCE、state、nonce 与移动端回调', () async {
    OidcService.debugHttpClient = MockClient((request) async {
      expect(request.url.path, '/admin/oidc/config');
      return http.Response(
        jsonEncode({
          'enabled': true,
          'client_id': 'shipyard-mobile',
          'authorization_endpoint': 'https://idp.example.test/authorize',
          'scopes': ['openid', 'profile', 'email'],
        }),
        200,
      );
    });

    final url = await OidcService.buildAuthorizeUrl(
      'https://shipyard.example.test',
    );
    final uri = Uri.parse(url);
    expect(uri.host, 'idp.example.test');
    expect(uri.queryParameters['client_id'], 'shipyard-mobile');
    expect(uri.queryParameters['redirect_uri'], 'shipyard://oidc/callback');
    expect(uri.queryParameters['response_type'], 'code');
    expect(uri.queryParameters['scope'], 'openid profile email');
    expect(uri.queryParameters['code_challenge_method'], 'S256');
    expect(uri.queryParameters['state'], isNotEmpty);
    expect(uri.queryParameters['nonce'], isNotEmpty);
    expect(uri.queryParameters['code_challenge'], isNotEmpty);
  });

  test('回调校验 state 并交换身份专属 API Key', () async {
    var exchangeCalled = false;
    OidcService.debugHttpClient = MockClient((request) async {
      if (request.url.path == '/admin/oidc/config') {
        return http.Response(
          jsonEncode({
            'enabled': true,
            'client_id': 'shipyard-mobile',
            'authorization_endpoint': 'https://idp.example.test/authorize',
            'scopes': ['openid'],
          }),
          200,
        );
      }
      if (request.url.path == '/admin/oidc/exchange') {
        exchangeCalled = true;
        final body = jsonDecode(request.body) as Map;
        expect(body['code'], 'oidc-code');
        expect(body['code_verifier'], hasLength(greaterThanOrEqualTo(43)));
        expect(body['nonce'], isNotEmpty);
        expect(body['redirect_uri'], 'shipyard://oidc/callback');
        return http.Response(jsonEncode({'api_key': 'oidc-api-key'}), 200);
      }
      return http.Response('not found', 404);
    });

    final authorizeUrl = await OidcService.buildAuthorizeUrl(
      'https://shipyard.example.test',
    );
    final state = Uri.parse(authorizeUrl).queryParameters['state']!;
    final result = await OidcService.completeFlow(
      Uri.parse('shipyard://oidc/callback?code=oidc-code&state=$state'),
    );

    expect(result, isNotNull);
    expect(result!.serverUrl, 'https://shipyard.example.test');
    expect(result.apiKey, 'oidc-api-key');
    expect(exchangeCalled, isTrue);
    expect(
      await OidcService.completeFlow(
        Uri.parse('shipyard://oidc/callback?code=oidc-code&state=$state'),
      ),
      isNull,
      reason: '流程状态必须一次性消费',
    );
  });

  test('state 不匹配时不交换授权码', () async {
    OidcService.debugHttpClient = MockClient((request) async {
      if (request.url.path == '/admin/oidc/config') {
        return http.Response(
          jsonEncode({
            'enabled': true,
            'client_id': 'shipyard-mobile',
            'authorization_endpoint': 'https://idp.example.test/authorize',
            'scopes': ['openid'],
          }),
          200,
        );
      }
      fail('state 不匹配时不能调用交换接口');
    });
    await OidcService.buildAuthorizeUrl('https://shipyard.example.test');

    expect(
      await OidcService.completeFlow(
        Uri.parse('shipyard://oidc/callback?code=oidc-code&state=forged'),
      ),
      isNull,
    );
  });
}
