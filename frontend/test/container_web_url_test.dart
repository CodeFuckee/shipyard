import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_portainer_flutter_module/services/container_web_url.dart';

/// Issue #45：已映射的 TCP 端口应可基于当前服务器主机名生成 HTTP 访问地址。
void main() {
  group('ContainerWebUrl.build', () {
    test('使用服务器主机名和宿主机端口生成 HTTP 地址', () {
      expect(
        ContainerWebUrl.build(
          apiUrl: 'https://docker.example.com:9443/api/',
          hostPort: '8080',
        ).toString(),
        'http://docker.example.com:8080',
      );
    });

    test('IPv6 服务器地址保留方括号并使用 HTTP（默认端口规范化）', () {
      expect(
        ContainerWebUrl.build(
          apiUrl: 'https://[2001:db8::1]:9443',
          hostPort: '80',
        ).toString(),
        'http://[2001:db8::1]',
      );
    });

    test('空地址、无主机地址、非法或越界端口不生成访问地址', () {
      for (final input in [
        (apiUrl: '', hostPort: '8080'),
        (apiUrl: 'not a uri', hostPort: '8080'),
        (apiUrl: 'https://docker.example.com', hostPort: ''),
        (apiUrl: 'https://docker.example.com', hostPort: 'abc'),
        (apiUrl: 'https://docker.example.com', hostPort: '0'),
        (apiUrl: 'https://docker.example.com', hostPort: '65536'),
      ]) {
        expect(
          ContainerWebUrl.build(apiUrl: input.apiUrl, hostPort: input.hostPort),
          isNull,
        );
      }
    });

    test('重复构建同一映射得到相同地址', () {
      final first = ContainerWebUrl.build(
        apiUrl: 'http://docker.example.com',
        hostPort: '3000',
      );
      final second = ContainerWebUrl.build(
        apiUrl: 'http://docker.example.com',
        hostPort: '3000',
      );

      expect(first, second);
    });
  });
}
