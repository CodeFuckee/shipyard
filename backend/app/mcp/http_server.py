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

from pydantic import AnyHttpUrl
from mcp.server.auth.settings import ClientRegistrationOptions
from mcp.server.auth.routes import (
    create_auth_routes,
    create_protected_resource_routes,
)

from app.core.config import PUBLIC_BASE_URL
from .server import app as _mcp_app

# ---- 创建 Streamable HTTP ASGI 应用 ----
# mcp 2.0.0: streamable_http_path 通过参数直接传入 streamable_http_app()
mcp_http_app = _mcp_app.streamable_http_app(streamable_http_path="/")

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
