"""
Mobile Portainer MCP Server 包。

本包实现了基于 MCP (Model Context Protocol) 的 Docker 管理服务，
让 AI 助手（如 Claude Code、Cursor 等）能够通过标准化的工具调用接口
管理 Docker 容器、镜像、网络、卷等资源。

=== 模块架构 ===

server.py         — MCP Server 入口，基于 MCPServer，使用 stdio 传输
http_server.py    — HTTP 传输层，将 MCP Server 导出为 ASGI 应用，可嵌入 FastAPI
tools.py          — 工具定义，注册 24 个 Docker 管理工具到 MCP Server
auth_provider.py  — OAuth 2.0 认证提供者，基于内存实现，与 API Key 系统集成
helpers.py        — 辅助函数，包括 Docker 客户端封装、数据库会话、API Key 校验

=== 认证体系 ===

本包支持三层认证：

1. stdio 模式：通过 MOBILE_PORTAINER_API_KEY 环境变量进行 API Key 认证
2. HTTP 模式（无 OAuth）：在 HTTP 请求头中携带 API Key（Authorization Bearer）
3. HTTP 模式（OAuth）：完整的 OAuth 2.0 授权码流程 + PKCE

=== 两种运行模式 ===

stdio（本地）：
    命令行直接启动，Claude Code 通过子进程通信。
    配置示例：
    {
      "mcpServers": {
        "mobile-portainer": {
          "command": "python",
          "args": ["-m", "app.mcp.server"],
          "env": {"MOBILE_PORTAINER_API_KEY": "your-api-key"}
        }
      }
    }

HTTP（远程）：
    作为 FastAPI 子应用挂载，支持远程访问。
    配置示例：
    {
      "mcpServers": {
        "mobile-portainer": {
          "type": "http",
          "url": "https://your-server:8000/mcp"
        }
      }
    }
"""
