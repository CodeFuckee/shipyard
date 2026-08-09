"""复现：https_proxy 转发时自动跟随 302，破坏网页授权回跳。

流水线 441 connect 测试诊断显示：授权页 confirm 后页面停在
"127.0.0.1:39409/connect/confirm"（内容变成登录页），源服务器
从未收到 /connect/callback。根因：https_proxy._forward 用
urllib.request.urlopen 转发请求，其 HTTPRedirectHandler **默认自动
跟随 302**——confirm 的 302 回跳（Location 指向源服务器
/connect/callback）被代理自己消费（urllib 跟随到源服务器处理回调），
浏览器收到的是跟随后的最终页面而非原始 302，授权流程中断。

本测试用本地 302 服务器验证转发请求必须原样返回 302（不跟随）。
修复前（urlopen 默认跟随）：返回 200（跟随后的页面）→ 断言失败；
修复后（NoRedirect opener）：返回 302 原样 → 通过。
"""

import http.server
import threading
import urllib.request

from https_proxy import _open_request


def _respond_302(self):
    self.send_response(302)
    self.send_header("Location", "https://target.example/cb?code=x")
    self.send_header("Content-Length", "0")
    self.end_headers()


class _RedirectServer(http.server.ThreadingHTTPServer):
    """对所有请求返回 302 → https://target.example/cb?code=x。"""

    def __init__(self):
        handler = type(
            "RedirectHandler",
            (http.server.BaseHTTPRequestHandler,),
            {
                "do_GET": _respond_302,
                "do_POST": _respond_302,
                "log_message": lambda *a, **k: None,
            },
        )
        super().__init__(("127.0.0.1", 0), handler)

    @property
    def base_url(self):
        return f"http://127.0.0.1:{self.server_port}"


class TestNoRedirectFollowed:
    """转发请求必须原样返回 302（浏览器负责跟随回跳）。"""

    def test_302_returned_as_is(self):
        srv = _RedirectServer()
        t = threading.Thread(target=srv.serve_forever, daemon=True)
        t.start()
        try:
            req = urllib.request.Request(f"{srv.base_url}/connect/confirm")
            resp = _open_request(req)
            assert resp.status == 302, (
                f"应原样返回 302（不跟随），实际 {resp.status}"
            )
            assert resp.headers.get("Location") == (
                "https://target.example/cb?code=x"
            ), "Location 头应原样透传"
        finally:
            srv.shutdown()
            srv.server_close()

    def test_302_post_not_followed(self):
        srv = _RedirectServer()
        t = threading.Thread(target=srv.serve_forever, daemon=True)
        t.start()
        try:
            req = urllib.request.Request(
                f"{srv.base_url}/connect/confirm",
                data=b"client_id=abc&redirect_uri=https%3A%2F%2Fx",
                method="POST",
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            )
            resp = _open_request(req)
            assert resp.status == 302, (
                f"POST 也应原样返回 302，实际 {resp.status}"
            )
        finally:
            srv.shutdown()
            srv.server_close()
