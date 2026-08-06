/// mixed content 提前检测:https 源页面请求 http 目标时,
/// 浏览器(Chrome/Firefox 等)一律阻止,探测必然失败。
/// 网页授权添加对话框在用户输入 URL 时实时调用,
/// 提前提示并禁用"继续"按钮,避免点击后才报错。
bool isMixedContentTarget(String targetUrl, {required bool sourceIsHttps}) {
  if (!sourceIsHttps) return false;
  final uri = Uri.tryParse(targetUrl.trim());
  if (uri == null) return false;
  return uri.scheme.toLowerCase() == 'http';
}
