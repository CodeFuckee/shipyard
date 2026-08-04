"""MCP 工具中镜像相关逻辑的测试（悬空镜像过滤）。"""

from unittest.mock import MagicMock, patch

import app.mcp.tools as tools_module


class _FakeServer:
    """模拟 MCPServer，仅收集 @server.tool 注册的原始函数。"""

    def __init__(self):
        self._tools = {}

    def tool(self, **kwargs):
        def decorator(fn):
            self._tools[fn.__name__] = fn
            return fn

        return decorator


def _register_tools():
    """注册全部 MCP 工具，返回 {函数名: 原始函数}。"""
    fake = _FakeServer()
    tools_module.register_all_tools(fake)
    return fake._tools


def _make_image(image_id, tags):
    """构造一个模拟的 docker Image 对象。"""
    img = MagicMock()
    img.id = image_id
    img.tags = tags
    img.short_id = image_id[:12]
    img.attrs = {"Created": "2024-01-01T00:00:00Z", "Size": 100}
    img.labels = {}
    return img


def _make_container(image_id, status="running"):
    container = MagicMock()
    container.attrs = {"Image": image_id}
    container.status = status
    return container


class TestMCPListImages:
    def test_list_images_excludes_dangling_images(self):
        """MCP 的 list_images 工具应排除 <none>:<none> 悬空镜像和无 tag 镜像。"""
        tools = _register_tools()
        list_images = tools["list_images"]

        nginx = _make_image("sha256:1111", ["nginx:latest"])
        dangling = _make_image("sha256:2222", ["<none>:<none>"])
        untagged = _make_image("sha256:3333", [])

        mock_client = MagicMock()
        mock_client.images.list.return_value = [nginx, dangling, untagged]
        mock_client.containers.list.return_value = []

        with patch.object(tools_module, "get_docker_client_safe", return_value=mock_client):
            result = list_images()

        assert len(result) == 1
        assert result[0]["id"] == "sha256:1111"
        assert result[0]["tags"] == ["nginx:latest"]


class TestMCPGetSystemInfo:
    def test_system_info_image_count_excludes_dangling_images(self):
        """MCP 的 get_system_info 工具统计镜像数时应排除悬空镜像。"""
        tools = _register_tools()
        get_system_info = tools["get_system_info"]

        nginx = _make_image("sha256:1111", ["nginx:latest"])
        dangling = _make_image("sha256:2222", ["<none>:<none>"])

        mock_client = MagicMock()
        mock_client.images.list.return_value = [nginx, dangling]
        mock_client.containers.list.return_value = [
            _make_container("sha256:1111", status="running"),
            _make_container("sha256:2222", status="exited"),
        ]

        with patch.object(tools_module, "get_docker_client_safe", return_value=mock_client):
            result = get_system_info()

        assert result["docker"]["images"] == 1
