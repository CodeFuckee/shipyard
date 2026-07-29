"""
Mobile Portainer MCP Server 入口点 — stdio 传输模式。

本模块通过 stdio（标准输入/输出）传输提供 MCP 服务，
让 AI 助手能通过 JSON-RPC 协议管理 Docker 资源。

=== stdio vs HTTP ===

stdio 模式：
  - MCP 客户端（如 Claude Code）作为父进程启动本模块
  - 通信通过 stdin/stdout 的 JSON-RPC 消息进行
  - 适合本地开发、单机使用
  - 认证通过 MOBILE_PORTAINER_API_KEY 环境变量

如需 HTTP 模式（远程访问），请使用 app.mcp.http_server，
它会自动挂载到 FastAPI 的 /mcp 路径。

=== 认证模式 ===

HTTP 模式下支持两种认证方式（通过 MCP_AUTH_ENABLED 环境变量控制）：

1. OAuth 2.0 模式（MCP_AUTH_ENABLED=true，默认）：
   - 完整的 OAuth 2.0 授权码流程 + PKCE
   - 动态客户端注册（DCR），持久化到 SQLite
   - 所有 Token 持久化存储，服务重启不丢失
   - API Key 可直接作为 Bearer token 使用（向后兼容）

2. 无认证模式（MCP_AUTH_ENABLED=false）：
   - MCP 端点无任何鉴权
   - 适用于开发环境或内网部署

=== 启动方式 ===

直接运行：
    python -m app.mcp.server

程序化调用：
    from app.mcp.server import app as mcp_app
    mcp_app.run(transport="stdio")

=== Claude Code 配置示例 ===

stdio 模式：
    {
      "mcpServers": {
        "mobile-portainer": {
          "command": "python",
          "args": ["-m", "app.mcp.server"],
          "env": {
            "MOBILE_PORTAINER_API_KEY": "your-api-key"
          }
        }
      }
    }

HTTP 模式（OAuth）：
    {
      "mcpServers": {
        "mobile-portainer": {
          "type": "http",
          "url": "https://your-server:8000/mcp"
        }
      }
    }

HTTP 模式（API Key，不走 OAuth）：
    {
      "mcpServers": {
        "mobile-portainer": {
          "type": "http",
          "url": "https://your-server:8000/mcp",
          "headers": {
            "Authorization": "Bearer ${MOBILE_PORTAINER_API_KEY}"
          }
        }
      }
    }

=== 依赖说明 ===

- MCPServer：MCP 协议的 Python 实现，提供 FastAPI 风格的装饰器 API
- docker-py：Docker Engine API 的 Python 客户端
- tools.py 中的 register_all_tools：向 MCPServer 实例注册所有 Docker 管理工具
"""

import logging
import os

from mcp.server import MCPServer
from mcp.server.auth.settings import AuthSettings, ClientRegistrationOptions

from app.core.config import MCP_AUTH_ENABLED, PUBLIC_BASE_URL
from app.db.database import SessionLocal
from .auth_provider import DatabaseOAuthProvider
from .helpers import get_docker_client_safe
from .tools import register_all_tools

# ---- 日志配置 ----
# 使用 "mcp.portainer" 命名空间，方便在应用中按模块过滤日志
logger = logging.getLogger("mcp.portainer")
logger.setLevel(logging.INFO)

# ---- 创建 MCPServer 实例 ----
# 根据 MCP_AUTH_ENABLED 环境变量决定是否启用 OAuth 认证
if MCP_AUTH_ENABLED:
    logger.info("MCP OAuth 认证已启用，issuer_url=%s/mcp", PUBLIC_BASE_URL)

    auth_provider = DatabaseOAuthProvider(
        session_factory=SessionLocal,
        api_key=os.environ.get("MOBILE_PORTAINER_API_KEY"),
    )

    app = MCPServer(
        "mobile-portainer",
        auth_server_provider=auth_provider,
        auth=AuthSettings(
            # issuer_url 必须在根路径，因为 MCP 客户端按 RFC 8414 规范
            # 在服务根路径（netloc）发现 OAuth 端点，而不是在 /mcp 子路径下
            issuer_url=f"{PUBLIC_BASE_URL}",
            # resource_server_url 指向实际的 MCP 协议端点路径
            resource_server_url=f"{PUBLIC_BASE_URL}/mcp",
            client_registration_options=ClientRegistrationOptions(
                enabled=True,
                client_secret_expiry_seconds=None,  # 客户端密钥永不过期
            ),
            required_scopes=[],
        ),
    )
else:
    logger.info("MCP OAuth 认证已禁用")
    app = MCPServer("mobile-portainer")

# ---- 注册所有 Docker 管理工具 ----
# 将 tools.py 中定义的 24 个工具函数注册到 MCP Server
# 这些工具按功能分为 5 组：容器(11)、镜像(4)、网络(2)、卷(3)、系统(4)
register_all_tools(app)

# ---- 启动时 Docker 连接检查 ----
# 在模块加载时尝试连接 Docker 守护进程，提前发现连接问题
# 连接失败不会阻止服务器启动——MCP 客户端调用工具时还会再次尝试连接
try:
    get_docker_client_safe()
    logger.info("Docker 守护进程连接成功")
except RuntimeError as e:
    logger.warning("无法连接到 Docker 守护进程：%s", e)


def main() -> None:
    """启动 MCP Server，使用 stdio 传输。

    本函数是模块的入口点，可通过 `python -m app.mcp.server` 调用。
    stdio 传输意味着：
    - 客户端通过标准输入发送 JSON-RPC 请求
    - 服务端通过标准输出返回 JSON-RPC 响应
    - 日志和调试信息通过标准错误输出（不影响协议通信）
    """
    app.run(transport="stdio")


# 支持直接运行：python -m app.mcp.server
if __name__ == "__main__":
    main()
