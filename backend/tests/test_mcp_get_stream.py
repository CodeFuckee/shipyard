"""
测试 MCP 服务器对独立 GET 流（SSE 长连接）的处理。

复现 bug：backend/docs/mcp-oauth-deadlock-investigation.md

客户端 mcp SDK（Hermes venv 的 mcp 1.28.1）在 OAuth auth flow 中
用 `async with self.context.lock` 全局锁包裹整个请求生命周期；
发送 notifications/initialized 后无条件启动 GET SSE 长连接，
而 httpx 的 auth flow 要求读完整个响应体才释放锁——GET 是长连接、
响应体永不结束 → 锁被永久占用 → 后续 tools/list POST 死锁 → 30s 超时。

服务器侧触发条件是"支持独立 GET 流"（GET /mcp 返回 200 + SSE）。
对照 GitLab MCP 服务器：GET /mcp 返回 405 Method Not Allowed →
客户端 GET 流立即失败、auth flow 快速结束并释放锁 → 无死锁。

修复目标：GET /mcp 返回 405（行为对齐 GitLab），POST /mcp 与
DELETE /mcp（会话清理）不受影响。
"""

import asyncio

import httpx

from app.mcp.http_server import mcp_http_app

REQUEST_TIMEOUT = 2.0


def _client() -> httpx.AsyncClient:
    """直接用 ASGI 传输测试 mcp_http_app（挂载于 FastAPI /mcp 之下）。

    注意：Starlette mount 会把真实请求路径重写为 "/" 再交给子应用，
    因此直接测 mcp_http_app 时请求路径用 "/"，等价于线上 GET /mcp。
    """
    transport = httpx.ASGITransport(app=mcp_http_app)
    return httpx.AsyncClient(transport=transport, base_url="http://127.0.0.1")


class TestGetStreamDisabled:
    """复现 bug：GET /mcp 支持独立 GET 流 → 客户端 OAuth 死锁。"""

    async def test_get_mcp_returns_405(self):
        """GET /mcp 必须返回 405（对齐 GitLab，禁用独立 GET 流）。

        修复前：GET 请求进入认证层（无 token 返回 401；有 token 则
        进入 _handle_get_request 返回 200 + 永续 SSE 长连接），
        都不会返回 405 —— 服务器仍"支持"独立 GET 流，触发客户端
        OAuth auth flow 锁死锁（docs/mcp-oauth-deadlock-investigation.md）。
        """
        async with _client() as client:
            resp = await asyncio.wait_for(
                client.get("/", headers={"Accept": "text/event-stream"}),
                timeout=REQUEST_TIMEOUT,
            )
        assert resp.status_code == 405, (
            f"GET /mcp 应返回 405 Method Not Allowed（对齐 GitLab），"
            f"实际返回 {resp.status_code}！\n"
            "服务器支持独立 GET 流会让客户端 SDK（mcp 1.28.1）的 OAuth "
            "auth flow 持有全局锁等待永续 SSE 响应体，后续 tools/list "
            "POST 死锁超时（见 docs/mcp-oauth-deadlock-investigation.md）。"
        )

    async def test_post_mcp_not_blocked(self):
        """POST /mcp 不受影响（认证层正常响应，而非 405）。"""
        async with _client() as client:
            resp = await asyncio.wait_for(
                client.post("/", json={}),
                timeout=REQUEST_TIMEOUT,
            )
        assert resp.status_code != 405, "405 拦截不得误伤 POST /mcp（MCP 主协议端点）"

    async def test_delete_mcp_not_blocked(self):
        """DELETE /mcp（会话清理）不受影响。"""
        async with _client() as client:
            resp = await asyncio.wait_for(
                client.delete("/"),
                timeout=REQUEST_TIMEOUT,
            )
        assert resp.status_code != 405, "405 拦截不得误伤 DELETE /mcp（会话清理）"
