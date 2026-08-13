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


class TestMCPSkillToolsRegistration:
    """issue #25：2 个 skill 工具也注册进 MCP server（共 35 个），
    供 hermes-agent 等外部 MCP 客户端通过 /mcp 端点调用。"""

    def test_register_all_tools_includes_skill_tools(self):
        """register_all_tools 共注册 35 个工具（33 个 Docker + 2 个 skill）。"""
        tools = _register_tools()
        assert len(tools) == 35
        assert "docker_mirror_pull" in tools
        assert "docker_pull_from_file" in tools

    def test_skill_tool_mirror_pull_executes(self):
        """MCP 注册的 docker_mirror_pull 直接调用 skill 实现（成功路径）。"""
        import app.agent.tools as agent_tools

        tools = _register_tools()
        mirror_pull = tools["docker_mirror_pull"]

        with patch.object(
            agent_tools,
            "puller",
            _FakePuller(results={("daocloud/nginx:1.25", "nginx:1.25"): (0, "ok")}),
        ):
            result = mirror_pull("nginx:1.25", mirror_prefixes=["daocloud"])
        assert "✅ 镜像拉取成功" in result

    def test_skill_tool_mirror_pull_invalid_name(self):
        """镜像名非法：返回参数错误提示，不抛异常。"""
        tools = _register_tools()
        mirror_pull = tools["docker_mirror_pull"]
        result = mirror_pull("bad name!")
        assert "❌ 参数错误" in result

    def test_skill_tool_pull_from_file_missing_file(self):
        """docker_pull_from_file 文件不存在：返回错误提示，不抛异常。"""
        tools = _register_tools()
        pull_from_file = tools["docker_pull_from_file"]
        result = pull_from_file("/nonexistent/Dockerfile")
        assert "❌" in result


class _FakePuller:
    """假镜像拉取器：按 (full, name) 返回预置结果，未预置的返回失败。"""

    def __init__(self, results):
        self._results = results

    def pull(self, full, name):
        return self._results.get((full, name), (1, "not found"))
