"""
MCP HTTP Server — Streamable HTTP 传输模式。

将 MCP Server 导出为 Streamable HTTP ASGI 应用，
可嵌入 FastAPI 或其他 ASGI 框架，支持远程 AI 助手访问。

=== 路由架构 ===

本模块同时处理两个层级的路由：

1. OAuth 路由（根路径）：
   - MCP 客户端按 RFC 8414 规范在服务根路径 (netloc) 发现 OAuth 端点
   - 即: /.well-known/oauth-authorization-server, /authorize, /token, /register
   - 这些路由需要注册到 FastAPI 的根路径上

2. MCP 协议端点（/mcp 子路径）：
   - 实际的 MCP JSON-RPC 协议通信端点
   - 通过 app.mount("/mcp", ...) 挂载

=== 用法 ===

    from app.mcp.http_server import (
        mcp_http_app, mcp_session_manager,
        mcp_oauth_routes, mcp_protected_resource_routes,
    )

    app = FastAPI()

    # 0. 注册 OAuth 路由（必须在根路径，先于 /mcp mount）
    for route in mcp_oauth_routes + mcp_protected_resource_routes:
        app.router.routes.append(route)

    # 1. 挂载 MCP 协议端点
    app.mount("/mcp", mcp_http_app)

=== Claude Code 配置示例 ===

    {
      "mcpServers": {
        "mobile-portainer": {
          "type": "http",
          "url": "https://your-server:8000/mcp"
        }
      }
    }
"""

from urllib.parse import urlparse

from pydantic import AnyHttpUrl
from starlette.responses import Response
from mcp.server.auth.settings import ClientRegistrationOptions
from mcp.server.auth.routes import (
    create_auth_routes,
    create_protected_resource_routes,
)
from mcp.server.transport_security import TransportSecuritySettings

from app.core.config import PUBLIC_BASE_URL
from .server import app as _mcp_app


def build_transport_security(public_base_url: str) -> TransportSecuritySettings:
    """构造 MCP 传输安全配置：允许公网 Host + 保留 DNS rebinding 防护。

    mcp SDK 的 streamable_http_app() 在未显式传入 transport_security 且
    host 参数为默认值 "127.0.0.1" 时，会自动启用 DNS rebinding 防护，
    allowed_hosts 仅包含 127.0.0.1/localhost/[::1]。

    外部客户端（Claude Code）通过公网域名访问时：
    - 无 token 请求在 RequireAuthMiddleware 层先 401，掩盖 Host 校验；
    - 携带有效 Bearer token 后进入 StreamableHTTPASGIApp，Host 校验
      生效 → 公网 Host 不在 allowed_hosts → 421 "Invalid Host header"。

    因此必须从 PUBLIC_BASE_URL 动态解析公网主机名加入 allowed_hosts，
    同时保留防护（非白名单 Host 仍被拒绝）。
    """
    parsed = urlparse(public_base_url)
    host = parsed.hostname or "localhost"
    scheme = parsed.scheme or "https"
    return TransportSecuritySettings(
        enable_dns_rebinding_protection=True,
        allowed_hosts=[
            # nginx `proxy_set_header Host $host` 转发的是不含端口的纯主机名
            #（$http_host 才保留端口）——必须同时放行两种形式，
            # 否则无端口 Host 不匹配通配端口模式 → 421 Invalid Host header
            host,
            f"{host}:*",
            "127.0.0.1:*",
            "localhost:*",
            "[::1]:*",
        ],
        allowed_origins=[
            f"{scheme}://{host}:*",
            "http://127.0.0.1:*",
            "http://localhost:*",
        ],
    )


class _DisallowGetStreamMiddleware:
    """禁用独立 GET 流（SSE 长连接），行为对齐 GitLab MCP 服务器。

    背景（见 docs/mcp-oauth-deadlock-investigation.md）：
    mcp SDK 客户端（Hermes 的 mcp 1.28.1）在 OAuth auth flow 中用
    `async with self.context.lock` 全局锁包裹整个请求生命周期；
    发送 notifications/initialized 后无条件启动 GET SSE 长连接，
    而 httpx 的 auth flow 要求读完整个响应体才释放锁——长连接
    响应体永不结束 → 锁被永久占用 → 后续 tools/list POST 死锁
    → connect_timeout 30s 超时。

    GitLab 的 MCP 服务器对 GET /mcp 返回 405 Method Not Allowed，
    客户端 GET 流请求立即失败、auth flow 快速结束并释放锁，因此
    无死锁。本中间件在认证层之前无条件拦截 GET，复刻该行为。

    注意：本项目工具均为请求-响应模式（tools/list、list_containers
    等），无 server-initiated 推送需求，禁用独立 GET 流不影响功能。
    """

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] == "http" and scope["method"] == "GET":
            response = Response(
                "Method Not Allowed: standalone GET stream disabled",
                status_code=405,
            )
            await response(scope, receive, send)
            return
        await self.app(scope, receive, send)


# ---- 创建 Streamable HTTP ASGI 应用 ----
# mcp 2.0.0: streamable_http_path 通过参数直接传入 streamable_http_app()
# 必须显式传入 transport_security（否则 SDK 自动启用仅 localhost 的
# DNS rebinding 防护，公网 Host 的请求返回 421 Invalid Host header）
mcp_http_app = _mcp_app.streamable_http_app(
    streamable_http_path="/",
    transport_security=build_transport_security(PUBLIC_BASE_URL),
)

# 在认证层之前包装，GET /mcp 无条件返回 405（禁用独立 GET 流，
# 解除客户端 OAuth auth flow 锁死锁）。main.py 仍以同一个名字
# 挂载到 /mcp 路径，无需改动。
mcp_http_app = _DisallowGetStreamMiddleware(mcp_http_app)

# ---- 导出会话管理器 ----
# mcp 2.0.0: session_manager 已从私有属性改为公开属性
mcp_session_manager = _mcp_app.session_manager

# ---- 创建根路径 OAuth 路由 ----
# MCP 客户端按 RFC 8414 规范在服务根路径发现 OAuth 端点，
# 而不是在 /mcp 子路径下，因此需要在 FastAPI 根路径注册这些路由
# 仅在启用 OAuth 认证时才创建这些路由

_root_url = AnyHttpUrl(PUBLIC_BASE_URL)
_resource_url = AnyHttpUrl(f"{PUBLIC_BASE_URL}/mcp")

if _mcp_app._auth_server_provider is not None:
    # 1. OAuth 授权服务器路由：/.well-known/..., /authorize, /token, /register
    mcp_oauth_routes = create_auth_routes(
        provider=_mcp_app._auth_server_provider,
        issuer_url=_root_url,
        client_registration_options=ClientRegistrationOptions(
            enabled=True,
            client_secret_expiry_seconds=None,
        ),
    )

    # 2. RFC 9728 受保护资源元数据路由
    # 客户端通过 WWW-Authenticate 头中的 resource_metadata URL 发现此端点
    mcp_protected_resource_routes = create_protected_resource_routes(
        resource_url=_resource_url,
        authorization_servers=[_root_url],
    )
else:
    mcp_oauth_routes = []
    mcp_protected_resource_routes = []
