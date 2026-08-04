"""容器日志接口 ANSI 转义序列处理测试。"""

import uuid
from unittest.mock import MagicMock, patch

import app.mcp.tools as tools_module
from app.core.utils import strip_ansi_escape_sequences
from app.db.models import APIKeyModel


def _make_log_container(log_bytes: bytes):
    """构造一个 logs() 返回指定字节的模拟容器对象。"""
    container = MagicMock()
    container.logs.return_value = log_bytes
    return container


class TestGetContainerLogs:
    def test_logs_strip_ansi_escape_sequences(self, client, db_session):
        """容器日志含 ANSI 转义序列（如 [31;1m）时，接口应返回剥离后的干净文本。

        复现场景：gitlab-runner 容器输出 \x1b[31;1m 前缀的颜色标记日志，
        群晖 Container Manager 会解析这些序列，而 Shipyard 直接透传导致前端乱码。
        """
        key_str = uuid.uuid4().hex
        db_session.add(APIKeyModel(key=key_str, note="测试"))
        db_session.commit()

        raw_log = (
            b"\x1b[31;1mERROR: Checking for jobs... forbidden\x1b[0m\n"
            b"\x1b[32;1mINFO: runner is healthy\x1b[0m\n"
        )
        mock_client = MagicMock()
        mock_client.containers.get.return_value = _make_log_container(raw_log)

        with patch(
            "app.routers.containers.get_docker_client", return_value=mock_client
        ):
            response = client.get(
                "/containers/abc123/logs?tail=100",
                headers={"X-API-Key": key_str},
            )

        assert response.status_code == 200
        logs = response.json()["logs"]
        # 不应包含 ANSI 转义序列（ESC 控制字符或残留的 [31;1m 标记）
        assert "\x1b" not in logs
        assert "[31;1m" not in logs
        assert "[0m" not in logs
        assert "ERROR: Checking for jobs... forbidden" in logs
        assert "INFO: runner is healthy" in logs


class TestStripAnsi:
    """strip_ansi_escape_sequences 纯函数测试。"""

    def test_strips_color_and_style_codes(self):
        """剥离颜色/粗体/重置等 CSI 序列，保留正文。"""
        text = "\x1b[31;1mERROR: fail\x1b[0m OK"
        assert strip_ansi_escape_sequences(text) == "ERROR: fail OK"

    def test_strips_cursor_and_clear_sequences(self):
        """剥离清行/移动光标等非颜色序列（docker build 进度条常用）。"""
        text = "\x1b[2K\x1b[1GStep 1/5\x1b[?25l"
        assert strip_ansi_escape_sequences(text) == "Step 1/5"

    def test_preserves_plain_text(self):
        """无 ANSI 序列的文本保持不变。"""
        text = "plain log line\n"
        assert strip_ansi_escape_sequences(text) == text


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
    fake = _FakeServer()
    tools_module.register_all_tools(fake)
    return fake._tools


class TestMCPContainerLogs:
    def test_mcp_get_container_logs_strips_ansi(self):
        """MCP 的 get_container_logs 工具同样应剥离 ANSI 转义序列。"""
        tools = _register_tools()
        get_container_logs = tools["get_container_logs"]

        container = MagicMock()
        container.logs.return_value = (
            b"\x1b[31;1mERROR: forbidden\x1b[0m\n"
        )
        mock_client = MagicMock()
        mock_client.containers.get.return_value = container

        with patch.object(
            tools_module, "get_docker_client_safe", return_value=mock_client
        ):
            result = get_container_logs("abc123", tail=100, timestamps=False)

        assert "\x1b" not in result["logs"]
        assert "ERROR: forbidden" in result["logs"]

    def test_mcp_build_project_strips_ansi_from_stream(self, tmp_path):
        """MCP 的 build_project 工具应剥离 docker build 输出的 ANSI 序列。"""
        tools = _register_tools()
        build_project = tools["build_project"]

        mock_client = MagicMock()
        mock_client.api.build.return_value = iter(
            [
                {"stream": "\x1b[1;32mStep 1/2 : FROM alpine\x1b[0m\n"},
                {"stream": "\x1b[2K\x1b[1GSuccessfully built abc123\x1b[0m\n"},
            ]
        )
        mock_client.images.get.return_value = MagicMock(id="sha256:abc123")

        # 模拟数据库查询返回状态为 idle 的项目
        mock_db = MagicMock()
        mock_db.query.return_value.filter.return_value.first.return_value = (
            MagicMock(status="idle")
        )
        mock_db_session = MagicMock()
        mock_db_session.return_value.__enter__.return_value = mock_db

        # 真实临时目录中创建非空 Dockerfile，供 _project_dir 检查通过
        project_dir = tmp_path / "p1"
        project_dir.mkdir()
        (project_dir / "Dockerfile").write_text("FROM alpine")

        with patch.object(
            tools_module, "get_docker_client_safe", return_value=mock_client
        ), patch.object(tools_module, "get_db_session", mock_db_session), patch.object(
            tools_module, "PROJECTS_DIR", str(tmp_path)
        ):
            result = build_project("p1")

        logs = result["logs"]
        for line in logs:
            assert "\x1b" not in line
        assert any("FROM alpine" in line for line in logs)
        assert any("Successfully built abc123" in line for line in logs)
