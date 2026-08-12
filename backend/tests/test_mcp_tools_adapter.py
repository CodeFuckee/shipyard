"""MCP 工具包装 — app/agent/mcp_tools.py。

将 MCP server 注册的 33 个 Docker 管理工具包装为 langchain 工具，供 AI agent
动态绑定（issue #21：前端可选择 tools 后传入 agent）。

覆盖：
- 正常路径：33 个工具全部可包装、元信息完整（名称/描述/分组/参数）
- 边界情况：schema 转换（bool 默认值 / 必填参数 / 可选参数 / 无参数工具）、
  未知工具名报错、重复名称去重、工具执行成功 / isError / 异常兜底
"""

import asyncio

import pytest

from app.agent import mcp_tools


# --- 元信息 ---


def test_meta_contains_all_33_tools():
    meta = mcp_tools.get_mcp_tools_meta()
    assert len(meta) == 33


def test_meta_entries_have_required_fields():
    for entry in mcp_tools.get_mcp_tools_meta():
        assert entry["name"], f"工具缺少 name: {entry}"
        assert entry["description"], f"工具 {entry['name']} 缺少 description"
        assert entry["group"], f"工具 {entry['name']} 缺少 group"
        assert isinstance(entry["parameters"], dict)


@pytest.mark.parametrize(
    "name,group",
    [
        ("list_containers", "容器"),
        ("get_container", "容器"),
        ("get_container_logs", "容器"),
        ("start_container", "容器"),
        ("stop_container", "容器"),
        ("restart_container", "容器"),
        ("kill_container", "容器"),
        ("pause_container", "容器"),
        ("unpause_container", "容器"),
        ("remove_container", "容器"),
        ("run_container", "容器"),
        ("list_images", "镜像"),
        ("get_image", "镜像"),
        ("pull_image", "镜像"),
        ("remove_image", "镜像"),
        ("list_networks", "网络"),
        ("get_network", "网络"),
        ("list_volumes", "卷"),
        ("get_volume", "卷"),
        ("remove_volume", "卷"),
        ("get_system_info", "系统"),
        ("get_system_usage", "系统"),
        ("list_stacks", "系统"),
        ("get_stack_containers", "系统"),
        ("list_projects", "项目"),
        ("get_project", "项目"),
        ("create_project", "项目"),
        ("delete_project", "项目"),
        ("get_project_file", "项目"),
        ("update_project_file", "项目"),
        ("build_project", "项目"),
        ("project_up", "项目"),
        ("project_down", "项目"),
    ],
)
def test_meta_group(name, group):
    entries = {e["name"]: e for e in mcp_tools.get_mcp_tools_meta()}
    assert entries[name]["group"] == group


def test_meta_parameters_include_bool_default():
    entries = {e["name"]: e for e in mcp_tools.get_mcp_tools_meta()}
    params = entries["list_containers"]["parameters"]
    # summary/all 是带默认值的 bool 参数
    assert params["summary"]["type"] == "boolean"
    assert params["summary"]["default"] is False
    assert params["all"]["default"] is True


def test_meta_parameters_include_required_string():
    entries = {e["name"]: e for e in mcp_tools.get_mcp_tools_meta()}
    params = entries["get_container"]["parameters"]
    assert params["container_id"]["type"] == "string"
    assert params["container_id"]["required"] is True


def test_meta_parameters_optional_string():
    entries = {e["name"]: e for e in mcp_tools.get_mcp_tools_meta()}
    params = entries["create_project"]["parameters"]
    # name/description/git_url 均为可选
    assert params["name"]["required"] is False
    assert params["git_url"]["required"] is False


# --- schema → pydantic 转换 ---


def test_schema_to_pydantic_bool_default():
    model = mcp_tools._schema_to_pydantic(
        "test",
        {
            "type": "object",
            "properties": {
                "summary": {"type": "boolean", "default": False},
                "all": {"type": "boolean", "default": True},
            },
            "required": ["summary"],
        },
    )
    inst = model(summary=True)
    assert inst.summary is True
    assert inst.all is True  # 默认值生效


def test_schema_to_pydantic_missing_required_field_raises():
    model = mcp_tools._schema_to_pydantic(
        "test", {"type": "object", "properties": {"id": {"type": "string"}}, "required": ["id"]}
    )
    with pytest.raises(Exception):
        model()  # 缺少必填字段


def test_schema_to_pydantic_empty_properties():
    model = mcp_tools._schema_to_pydantic("test", {"type": "object", "properties": {}})
    assert model() is not None  # 无参数工具可构造


def test_schema_to_pydantic_optional_string_default_none():
    model = mcp_tools._schema_to_pydantic(
        "test",
        {
            "type": "object",
            "properties": {"name": {"type": "string", "description": "项目名"}},
        },
    )
    inst = model()
    assert inst.name is None


# --- 工具包装 ---


def test_build_tools_all_33_succeed():
    names = [e["name"] for e in mcp_tools.get_mcp_tools_meta()]
    tools = mcp_tools.build_tools(names)
    assert len(tools) == 33
    for t in tools:
        assert t.name in names
        assert t.description
        assert t.args_schema is not None


def test_build_tools_dedup_and_ignore_empty():
    tools = mcp_tools.build_tools(["list_containers", "list_containers", "", "  "])
    assert len(tools) == 1
    assert tools[0].name == "list_containers"


def test_build_tools_empty_list():
    assert mcp_tools.build_tools([]) == []


def test_build_tools_unknown_name_raises():
    with pytest.raises(ValueError):
        mcp_tools.build_tools(["not_a_real_tool"])


def test_build_tools_mixed_known_unknown_raises():
    with pytest.raises(ValueError):
        mcp_tools.build_tools(["list_containers", "not_a_real_tool"])


# --- 工具调用 ---


class FakeCallResult:
    def __init__(self, content, is_error=False):
        self.content = content
        self.isError = is_error


@pytest.fixture
def fake_server(monkeypatch):
    """mock MCPServer.call_tool，避免真实 Docker 连接。

    mode 控制返回行为：ok（成功）/ fail（isError）/ raise（抛异常）。
    工具名统一使用真实存在的 list_containers。
    """

    class FakeServer:
        def __init__(self):
            self.calls = []
            self.mode = "ok"

        async def call_tool(self, name, arguments, context=None):
            self.calls.append((name, arguments))
            if self.mode == "raise":
                raise RuntimeError("模拟工具内部异常")
            if self.mode == "fail":
                return FakeCallResult(
                    [{"type": "text", "text": "容器不存在"}], is_error=True
                )
            return FakeCallResult([{"type": "text", "text": f"{name} 执行成功"}])

    fake = FakeServer()
    monkeypatch.setattr(mcp_tools, "_get_mcp_server", lambda: fake)
    return fake


def _ainvoke(tool, kwargs):
    """运行 async 工具调用并收集结果。"""
    return asyncio.run(tool.ainvoke(kwargs))


def test_tool_call_success(fake_server):
    tool = mcp_tools.build_tools(["list_containers"])[0]
    result = _ainvoke(tool, {"summary": False, "all": True})
    assert "list_containers 执行成功" in result
    assert fake_server.calls == [("list_containers", {"summary": False, "all": True})]


def test_tool_call_is_error_returns_message(fake_server):
    fake_server.mode = "fail"
    tool = mcp_tools.build_tools(["list_containers"])[0]
    result = _ainvoke(tool, {"summary": False})
    assert "执行失败" in result
    assert "容器不存在" in result


def test_tool_call_exception_returns_message(fake_server):
    fake_server.mode = "raise"
    tool = mcp_tools.build_tools(["list_containers"])[0]
    result = _ainvoke(tool, {"summary": False})
    assert "模拟工具内部异常" in result


def test_tool_call_optional_defaults_applied(fake_server):
    """缺省参数使用 schema 默认值（all=True），不抛错。"""
    tool = mcp_tools.build_tools(["list_containers"])[0]
    result = _ainvoke(tool, {"summary": False})
    assert "list_containers 执行成功" in result
    assert fake_server.calls == [("list_containers", {"summary": False, "all": True})]


def test_tool_call_missing_required_arg_raises(fake_server):
    """缺必填参数（container_id）时 pydantic 校验失败抛异常。"""
    tool = mcp_tools.build_tools(["get_container"])[0]
    with pytest.raises(Exception):
        _ainvoke(tool, {})
