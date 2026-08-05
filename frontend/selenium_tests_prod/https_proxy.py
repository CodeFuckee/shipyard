"""本地 HTTPS 反向代理：解决 https 源 + http 目标服务器的 mixed content 阻止。

网页授权添加测试场景：源服务器 https://home.chenkaidi.top:507 的前端页面
请求 http://10.0.0.122:8080 时会被浏览器 mixed content 策略阻止（console:
Mixed Content ... net::ERR_FAILED），导致探测/注册/授权流程全部失败。
通过本地 HTTPS 代理把 https://127.0.0.1:<port> 转发到 http://目标服务器，
浏览器侧 https→https 无 mixed content 问题。

- 自签证书由 openssl 生成（macOS/Linux 自带），Chrome 通过
  --ignore-certificate-errors 忽略证书错误
- 转发时替换 Host 头为目标主机（nginx 按 Host 路由）
- 透传全部响应头（CORS / Set-Cookie / 302 Location），保持流程语义
"""

import base64
import hashlib
import http.server
import os
import ssl
import subprocess
import tempfile
import threading
import urllib.error
import urllib.request
from urllib.parse import urlparse

_SSL_CONTEXT = ssl._create_unverified_context()


def _cert_spki_hash(cert_path: str) -> str:
    """计算证书公钥的 SHA-256 SPKI hash（Chrome 信任指定证书用）。

    格式与 --ignore-certificate-errors-spki-list 一致：
    base64(SHA-256(SubjectPublicKeyInfo DER))。
    """
    pubkey = subprocess.check_output(
        ["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"]
    ).decode()
    lines = [l for l in pubkey.splitlines() if "-----" not in l]
    der = base64.b64decode("".join(lines))
    return base64.b64encode(hashlib.sha256(der).digest()).decode()


def _handle_options(self):
    """拦截 OPTIONS：模拟后端已支持 Private Network Access。

    真实后端（FastAPI CORSMiddleware）对带
    Access-Control-Request-Private-Network: true 的 preflight 返回
    400 "Disallowed CORS private-network"（不返回
    Access-Control-Allow-Private-Network 头），导致公网页面请求
    私有网络目标被浏览器 PNA 策略阻止。这里模拟修复后的行为：
    返回 CORS 允许头 + PNA 允许头。
    """
    self.send_response(200)
    origin = self.headers.get("Origin", "*")
    self.send_header("Access-Control-Allow-Origin", origin)
    self.send_header("Access-Control-Allow-Credentials", "true")
    self.send_header(
        "Access-Control-Allow-Methods",
        "DELETE, GET, HEAD, OPTIONS, PATCH, POST, PUT",
    )
    self.send_header(
        "Access-Control-Allow-Headers",
        self.headers.get("Access-Control-Request-Headers", "*"),
    )
    self.send_header("Access-Control-Allow-Private-Network", "true")
    self.send_header("Access-Control-Max-Age", "600")
    self.send_header("Content-Length", "0")
    self.end_headers()


def _forward(self):
    """BaseHTTPRequestHandler 转发方法（do_GET/do_POST 共用）。"""
    # 读取请求体
    length = int(self.headers.get("Content-Length", 0) or 0)
    body = self.rfile.read(length) if length else None

    # 转发请求：替换 Host 头为目标主机（nginx 按 Host 路由站点）
    parsed = urlparse(self.target)
    target_host = parsed.hostname or ""
    if parsed.port:
        target_host = f"{target_host}:{parsed.port}"
    headers = {
        k: v for k, v in self.headers.items() if k.lower() != "host"
    }
    headers["Host"] = target_host

    req = urllib.request.Request(
        f"{self.target}{self.path}",
        data=body,
        method=self.command,
        headers=headers,
    )
    try:
        resp = urllib.request.urlopen(req, context=_SSL_CONTEXT, timeout=30)
        status, resp_headers, resp_body = resp.status, resp.headers, resp.read()
    except urllib.error.HTTPError as e:
        status, resp_headers, resp_body = e.code, e.headers, e.read()
    except Exception as e:
        # 转发失败：返回 502，便于测试排查
        self.send_response(502)
        self.send_header("Content-Type", "text/plain")
        msg = f"proxy error: {type(e).__name__}: {e}".encode()
        self.send_header("Content-Length", str(len(msg)))
        self.end_headers()
        self.wfile.write(msg)
        return

    self.send_response(status)
    for k, v in resp_headers.items():
        if k.lower() in ("connection", "transfer-encoding", "content-length"):
            continue
        self.send_header(k, v)
    self.send_header("Content-Length", str(len(resp_body)))
    self.end_headers()
    self.wfile.write(resp_body)


class HttpsReverseProxy:
    """把 https://127.0.0.1:<port> 转发到目标 http/https 服务器的反向代理。"""

    def __init__(self, target: str, host: str = "127.0.0.1", port: int = 0):
        self.target = target.rstrip("/")
        self.host = host
        self.port = port
        self._server = None
        self._thread = None
        self._cert_dir = None
        self.spki = ""  # 证书公钥 SPKI hash（传给 Chrome 精确信任）

    def start(self):
        """启动代理（生成自签证书 + 监听 https）。"""
        self._cert_dir = tempfile.mkdtemp(prefix="proxy-cert-")
        cert = os.path.join(self._cert_dir, "cert.pem")
        key = os.path.join(self._cert_dir, "key.pem")
        subprocess.run(
            [
                "openssl", "req", "-x509", "-newkey", "rsa:2048",
                "-keyout", key, "-out", cert, "-days", "30", "-nodes",
                "-subj", "/CN=127.0.0.1",
            ],
            check=True, capture_output=True,
        )

        handler = type(
            "ProxyHandler",
            (http.server.BaseHTTPRequestHandler,),
            {
                "target": self.target,
                "do_GET": _forward,
                "do_POST": _forward,
                "do_OPTIONS": _handle_options,
                "log_message": lambda *a, **k: None,
            },
        )
        self._server = http.server.ThreadingHTTPServer((self.host, self.port), handler)
        self.port = self._server.server_address[1]

        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(cert, key)
        self._server.socket = ctx.wrap_socket(self._server.socket, server_side=True)

        self.spki = _cert_spki_hash(cert)

        self._thread = threading.Thread(
            target=self._server.serve_forever, daemon=True
        )
        self._thread.start()

    @property
    def base_url(self) -> str:
        return f"https://{self.host}:{self.port}"

    def stop(self):
        if self._server:
            self._server.shutdown()
            self._server.server_close()
            self._server = None
