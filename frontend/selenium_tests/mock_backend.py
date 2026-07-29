#!/usr/bin/env python3
"""Mock Portainer API 服务器。

同时提供：
1. Flutter Web 静态文件服务（从 ../build/web 目录）
2. Portainer API mock 端点

生产模式下 Flutter Web 的 LoginScreen._serverUrl 返回 Uri.base.origin，
即前后端同源，所以必须用同一个端口。
"""

import json
import mimetypes
import os
import sys
from http.server import HTTPServer, SimpleHTTPRequestHandler
from socketserver import ThreadingMixIn


class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    """多线程 HTTP 服务器，支持并发请求处理。

    Flutter Web 应用在加载时需要并发请求多个资源（CanvasKit WASM、
    dart.js、字体、素材等），单线程服务器串行处理会导致资源加载阻塞、
    超时，可能触发 Chromium 渲染进程崩溃（"There is an unknown failure"）。
    """
    daemon_threads = True  # 守护线程，主线程退出时自动清理

# 显式注册关键 MIME 类型，确保在 slim Docker 镜像中也正确识别
_mime_overrides = {
    '.wasm': 'application/wasm',
    '.js': 'application/javascript',
    '.mjs': 'application/javascript',
    '.dart': 'application/dart',
    '.json': 'application/json',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.svg': 'image/svg+xml',
    '.ico': 'image/vnd.microsoft.icon',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2',
    '.ttf': 'font/ttf',
    '.otf': 'font/otf',
}
for ext, mime in _mime_overrides.items():
    mimetypes.add_type(mime, ext)

MOCK_API_KEY = "mock-api-key-for-testing"
FLUTTER_BUILD_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "web")
PORT = int(os.environ.get("MOCK_BACKEND_PORT", "9000"))

SAMPLE_CONTAINERS = [
    {
        "id": "abc123def456",
        "name": "nginx-proxy",
        "image": "nginx:alpine",
        "status": "running",
        "ports": "80:80, 443:443",
        "stack": "web",
        "created": "2024-01-01T00:00:00Z",
    },
    {
        "id": "def789ghi012",
        "name": "redis-cache",
        "image": "redis:7-alpine",
        "status": "running",
        "ports": "6379:6379",
        "stack": "",
        "created": "2024-01-02T00:00:00Z",
    },
    {
        "id": "ghi345jkl678",
        "name": "old-app",
        "image": "myapp:1.0",
        "status": "exited",
        "ports": "",
        "stack": "",
        "created": "2024-01-03T00:00:00Z",
    },
    {
        "id": "jkl901mno234",
        "name": "postgres-db",
        "image": "postgres:15",
        "status": "running",
        "ports": "5432:5432",
        "stack": "database",
        "created": "2024-01-04T00:00:00Z",
    },
]

SAMPLE_IMAGES = [
    {"id": "sha256:abc123", "name": "nginx:alpine", "size": "40MB", "created": "2024-01-01T00:00:00Z"},
    {"id": "sha256:def456", "name": "redis:7-alpine", "size": "30MB", "created": "2024-01-02T00:00:00Z"},
    {"id": "sha256:ghi789", "name": "postgres:15", "size": "200MB", "created": "2024-01-03T00:00:00Z"},
]

SAMPLE_VOLUMES = {
    "Volumes": [
        {"Name": "nginx_data", "Driver": "local", "Mountpoint": "/var/lib/docker/volumes/nginx_data"},
        {"Name": "postgres_data", "Driver": "local", "Mountpoint": "/var/lib/docker/volumes/postgres_data"},
    ]
}

SAMPLE_NETWORKS = [
    {"Name": "bridge", "Id": "abc123", "Driver": "bridge", "Scope": "local"},
    {"Name": "host", "Id": "def456", "Driver": "host", "Scope": "local"},
]

SAMPLE_STACKS = ["web", "database"]

SAMPLE_INFO = {
    "version": "2.19.0",
    "platform": "linux",
    "containers": 3,
    "images": 5,
    "volumes": 2,
    "networks": 3,
}

SAMPLE_USAGE = {
    "cpu": 35.5,
    "memory": 62.3,
    "disk": 45.1,
}


class MockHandler(SimpleHTTPRequestHandler):
    """处理 API 请求 + 静态文件回退。"""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=FLUTTER_BUILD_DIR, **kwargs)

    def log_message(self, format, *args):
        sys.stderr.write("[mock_backend] %s - %s\n" % (self.address_string(), format % args))

    def _send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self._send_security_headers()
        self.end_headers()
        self.wfile.write(body)

    def _send_security_headers(self):
        """添加跨域隔离头，使 SharedArrayBuffer 可用（CanvasKit/Skwasm 需要）。

        使用 credentialless 而非 require-corp：
        - credentialless 仍然启用跨域隔离和 SharedArrayBuffer
        - 但不要求跨域资源显式发送 Cross-Origin-Resource-Policy 头
        - 跨域资源会以无凭证模式加载，兼容性更好
        - Chrome 96+ 和 Chromium 120+ 均支持
        """
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "credentialless")

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        if length > 0:
            return self.rfile.read(length)
        return b""

    def _serve_static_file(self):
        """手动处理静态文件请求，确保 MIME 类型和跨域隔离头正确设置。"""
        path = self.translate_path(self.path)
        path = path.split("?")[0]

        # 安全检查：确保请求路径在 FLUTTER_BUILD_DIR 内
        real_path = os.path.realpath(path)
        real_root = os.path.realpath(FLUTTER_BUILD_DIR)
        if not real_path.startswith(real_root + os.sep) and real_path != real_root:
            self.send_error(404, "File not found")
            return

        if not os.path.exists(path) or os.path.isdir(path):
            # 如果是目录或文件不存在，回退到 index.html（SPA 路由）
            if os.path.isdir(path) or not os.path.exists(path):
                path = os.path.join(FLUTTER_BUILD_DIR, "index.html")
                if not os.path.exists(path):
                    self.send_error(404, "File not found")
                    return

        try:
            ctype = mimetypes.guess_type(path)[0] or "application/octet-stream"
            with open(path, "rb") as f:
                content = f.read()
                self.send_response(200)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(content)))
                self.send_header("Access-Control-Allow-Origin", "*")
                self._send_security_headers()
                self.end_headers()
                self.wfile.write(content)
        except OSError:
            self.send_error(404, "File not found")

    def do_POST(self):
        if self.path == "/admin/login":
            user = self.headers.get("X-Admin-User", "")
            password = self.headers.get("X-Admin-Pass", "")
            if user.startswith("__invalid") or password.startswith("__invalid"):
                self._send_json({"message": "Invalid credentials"}, 401)
            else:
                self._send_json({"key": MOCK_API_KEY})
        elif self.path == "/api/auth":
            self._send_json({"jwt": MOCK_API_KEY})
        else:
            self._send_json({"message": "not found"}, 404)

    def do_GET(self):
        path = self.path.split("?")[0]

        if path == "/containers/summary":
            self._send_json(SAMPLE_CONTAINERS)
        elif path == "/images":
            self._send_json(SAMPLE_IMAGES)
        elif path == "/volumes":
            self._send_json(SAMPLE_VOLUMES)
        elif path == "/networks":
            self._send_json(SAMPLE_NETWORKS)
        elif path == "/stacks":
            self._send_json(SAMPLE_STACKS)
        elif path == "/info":
            self._send_json(SAMPLE_INFO)
        elif path == "/usage":
            self._send_json(SAMPLE_USAGE)
        elif path == "/admin/keys":
            self._send_json([])
        elif path.startswith("/containers/") and "/files" in path:
            self._send_json([])
        elif path.startswith("/containers/") and "/logs" in path:
            self._send_json({"logs": "[mock] no logs available"})
        elif path.startswith("/containers/") and "/download" in path:
            self._send_json({}, 404)
        elif path == "/git/version":
            self._send_json({"version": "2.19.0"})
        elif path == "/ports/available":
            self._send_json({"ports": []})
        elif path.startswith("/ws/"):
            self._send_json({"message": "WebSocket not supported in mock"}, 400)
        elif path == "/api/auth":
            self._send_json({"message": "use POST"}, 405)
        elif path == "/admin/keys":
            self._send_json([])
        else:
            self._serve_static_file()

    def do_DELETE(self):
        self._send_json({}, 204)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS, HEAD")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-API-Key, X-Admin-User, X-Admin-Pass")
        self._send_security_headers()
        self.end_headers()


def main():
    if not os.path.isdir(FLUTTER_BUILD_DIR):
        print(f"[mock_backend] WARNING: Flutter build dir not found: {FLUTTER_BUILD_DIR}")
        print("[mock_backend] Run 'flutter build web' first, or set MOCK_BACKEND_PORT and serve separately.")

    server = ThreadingHTTPServer(("0.0.0.0", PORT), MockHandler)
    print(f"[mock_backend] Listening on http://0.0.0.0:{PORT} (threaded)")
    print(f"[mock_backend] Serving static files from: {FLUTTER_BUILD_DIR}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()


if __name__ == "__main__":
    main()
