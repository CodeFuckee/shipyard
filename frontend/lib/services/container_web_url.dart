/// 根据当前 Docker 服务地址与宿主机映射端口生成容器网页访问地址。
///
/// Docker 的传输层协议不能可靠推断应用层协议；Issue #45 已确认统一使用 HTTP。
class ContainerWebUrl {
  const ContainerWebUrl._();

  /// 仅在服务地址包含有效主机名、且宿主机端口处于有效范围时返回 HTTP 地址。
  static Uri? build({required String apiUrl, required String hostPort}) {
    final serverUri = Uri.tryParse(apiUrl.trim());
    final port = int.tryParse(hostPort.trim());
    if (serverUri == null ||
        serverUri.host.isEmpty ||
        port == null ||
        port < 1 ||
        port > 65535) {
      return null;
    }

    return Uri(scheme: 'http', host: serverUri.host, port: port);
  }
}
