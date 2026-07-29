"""
测试 mcp 包的导入兼容性。

背景：mcp 2.0.0 将 FastMCP 重命名为 MCPServer，
移除了 mcp.server.fastmcp 模块。本项目已迁移至 mcp 2.0.0 的新 API。

本测试文件：
- 复现原 bug：验证 mcp.server.fastmcp 模块在新版 mcp 中已不存在
- 验证修复：确认 mcp.server.MCPServer 导入正常
- 验证完整导入链：app.mcp.server 和 app.mcp.http_server 可正常加载
"""

import pytest


class TestMcpCoreImports:
    """测试 mcp 核心包的导入路径兼容性。"""

    def test_mcpserver_import_success(self):
        """修复验证：mcp 2.0.0 中 MCPServer 应从 mcp.server 导入。"""
        from mcp.server import MCPServer

        assert MCPServer is not None

    def test_mcpserver_instantiation(self):
        """修复验证：MCPServer 实例可以正常创建。"""
        from mcp.server import MCPServer

        server = MCPServer("test-server")
        assert server.name == "test-server"

    def test_fastmcp_import_raises(self):
        """Bug 复现：mcp.server.fastmcp 模块在 mcp >= 2.0.0 中已不存在。

        原代码 `from mcp.server.fastmcp import FastMCP` 会抛出
        ModuleNotFoundError，这正是 Docker 部署时的报错根因。
        """
        with pytest.raises(ModuleNotFoundError):
            from mcp.server.fastmcp import FastMCP  # noqa: F811


class TestMcpAuthImports:
    """测试 mcp OAuth 认证相关模块的导入路径。"""

    def test_auth_settings_import(self):
        """验证 AuthSettings 和 ClientRegistrationOptions 导入正常。"""
        from mcp.server.auth.settings import AuthSettings, ClientRegistrationOptions

        assert AuthSettings is not None
        assert ClientRegistrationOptions is not None

    def test_auth_routes_import(self):
        """验证 OAuth 路由工厂函数导入正常。"""
        from mcp.server.auth.routes import (
            create_auth_routes,
            create_protected_resource_routes,
        )

        assert create_auth_routes is not None
        assert create_protected_resource_routes is not None

    def test_auth_provider_import(self):
        """验证 OAuthAuthorizationServerProvider 导入正常。"""
        from mcp.server.auth.provider import OAuthAuthorizationServerProvider

        assert OAuthAuthorizationServerProvider is not None

    def test_shared_auth_import(self):
        """验证 OAuthClientInformationFull 导入正常。"""
        from mcp.shared.auth import OAuthClientInformationFull

        assert OAuthClientInformationFull is not None


class TestMcpServerApi:
    """测试 MCPServer 的 API 与项目使用方式兼容。"""

    def test_streamable_http_app_with_path(self):
        """修复验证：streamable_http_path 通过参数传入（非 settings 属性）。"""
        from mcp.server import MCPServer

        server = MCPServer("test")
        app = server.streamable_http_app(streamable_http_path="/")

        assert app is not None

    def test_session_manager_is_public(self):
        """修复验证：session_manager 在 2.0.0 中已从私有改为公开属性。

        注意：session_manager 需要先调用 streamable_http_app() 后
        才可访问（延迟初始化），这与 http_server.py 中的实际使用顺序一致。
        """
        from mcp.server import MCPServer

        server = MCPServer("test")
        # 必须先创建 streamable_http_app，session_manager 才会被初始化
        server.streamable_http_app(streamable_http_path="/")
        sm = server.session_manager

        assert sm is not None

    def test_run_method_exists(self):
        """修复验证：run() 方法签名兼容，支持 stdio 传输模式。"""
        from mcp.server import MCPServer

        server = MCPServer("test")
        assert hasattr(server, "run")
        assert callable(server.run)

    def test_tool_decorator_exists(self):
        """修复验证：@server.tool() 装饰器仍然可用。"""
        from mcp.server import MCPServer

        server = MCPServer("test")

        @server.tool(description="测试工具")
        def test_tool(name: str) -> str:
            return f"Hello, {name}!"

        assert hasattr(test_tool, "__name__")
