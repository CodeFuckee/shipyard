#!/usr/bin/env python3
"""Mock Portainer API 服务器。

同时提供：
1. Flutter Web 静态文件服务（从 ../build/web 目录）
2. Portainer API mock 端点

生产模式下 Flutter Web 的 LoginScreen._serverUrl 返回 Uri.base.origin，
即前后端同源，所以必须用同一个端口。
"""

import base64
import hashlib
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
# WebSocket 握手 GUID（RFC 6455 固定值）
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

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

# ----------------------------------------------------------
# AI agent mock（issue #39：Playwright E2E 测试需要）
# 前端 AgentService 调用 /admin/agent/* 接口：
#   - GET  /admin/agent/tools                 拉取工具列表
#   - GET  /admin/agent/chat-sessions         历史会话列表
#   - GET  /admin/agent/chat-sessions/{id}    历史会话消息
#   - GET  /admin/agent/debug-logs            调试日志列表
#   - POST /admin/agent/chat/stream           SSE 流式对话
# ----------------------------------------------------------
MOCK_AGENT_TOOLS = {
    "skills": [
        {"id": "status", "name": "container_status",
         "description": "查看所有容器的运行状态"},
    ],
    "tools": [],
}

# SSE 流式回复：token 增量 + reply 兜底 + session_id（后端格式）
MOCK_AI_REPLY_TOKENS = [
    "好的，", "我来", "查看", "容器", "状态。\n",
    "当前共有 3 个容器：nginx-proxy（运行中）、redis-cache（运行中）、old-app（已退出）。",
]

MOCK_AI_REPLY_FULL = "".join(MOCK_AI_REPLY_TOKENS)


def _sse_frame(event_type, payload):
    """把事件 dict 编码为 SSE 帧（与后端 agent.py 一致）。"""
    import json as _json
    data = _json.dumps(payload, ensure_ascii=False)
    return f"event: {event_type}\ndata: {data}\n\n".encode("utf-8")


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
        elif self.path == "/admin/agent/chat/stream":
            self._send_agent_sse()
        elif self.path == "/api/auth":
            self._send_json({"jwt": MOCK_API_KEY})
        else:
            self._send_json({"message": "not found"}, 404)

    def _handle_websocket_upgrade(self):
        """处理 WebSocket 升级握手（RFC 6455），保持连接供前端事件流使用。

        前端 home_screen 通过 WebSocketChannel.connect 连接 /ws/events，
        握手失败会在浏览器控制台产生 console.error（issue #39 要求
        "整个操作流程中控制台没有报错"，因此 mock 必须握手成功）。
        握手后静默保持连接（不解析帧），客户端断开即结束。
        """
        key = self.headers.get("Sec-WebSocket-Key", "")
        accept = base64.b64encode(
            hashlib.sha1((key + WS_GUID).encode("utf-8")).digest()
        ).decode("utf-8")
        self.send_response(101, "Switching Protocols")
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept)
        self.end_headers()
        # 保持连接：持续读取客户端数据直到断开（不解析帧，测试场景足够）
        try:
            while True:
                data = self.rfile.read(4096)
                if not data:
                    break
        except Exception:
            pass

    def do_GET(self):
        # WebSocket 升级请求：先于普通 GET 路由处理
        if self.headers.get("Upgrade", "").lower() == "websocket":
            self._handle_websocket_upgrade()
            return
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
        elif path == "/admin/agent/tools":
            self._send_json(MOCK_AGENT_TOOLS)
        elif path == "/admin/agent/chat-sessions":
            # 空历史：每次都是全新会话（测试无需跨会话状态）
            self._send_json([])
        elif path.startswith("/admin/agent/chat-sessions/"):
            # 历史会话详情：mock 返回空消息列表
            self._send_json({"messages": []})
        elif path == "/admin/agent/debug-logs":
            self._send_json([])
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

    def do_PUT(self):
        """支持 PUT 请求（agent 历史会话更新等），避免 501 触发控制台报错。"""
        path = self.path.split("?")[0]
        if path.startswith("/admin/agent/chat-sessions/"):
            # 更新历史会话（issue #38）：mock 直接返回成功
            self._send_json({"id": 1, "messages": [], "reply": "", "events": []})
        else:
            self._send_json({}, 200)

    def do_DELETE(self):
        self._send_json({}, 204)

    def _send_agent_sse(self):
        """模拟 /admin/agent/chat/stream 的 SSE 流式回复。

        事件序列与后端 agent.py 保持一致：token 增量 -> reply 兜底，
        末尾推送 session_id（前端据此记录会话 id）。
        """
        try:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("X-Accel-Buffering", "no")
            self.send_header("Access-Control-Allow-Origin", "*")
            self._send_security_headers()
            self.end_headers()

            # token 增量事件（每帧间隔很小，模拟流式）
            for token in MOCK_AI_REPLY_TOKENS:
                self.wfile.write(_sse_frame("token", {"content": token}))
                self.wfile.flush()
            # reply 兜底事件（token 已拼出完整回复，前端不会重复追加）
            self.wfile.write(_sse_frame("reply", {"content": MOCK_AI_REPLY_FULL}))
            self.wfile.flush()
            # 会话 id（issue #38：首次对话后前端持有 id）
            self.wfile.write(_sse_frame("session_id", {"session_id": 1}))
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            # 客户端中途断开：静默结束
            pass

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
