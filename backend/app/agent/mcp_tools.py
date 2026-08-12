"""MCP 工具包装 — 将 MCP server 的 Docker 管理工具适配为 langchain 工具。

背景（issue #21）：前端 AI agent 聊天框支持用户选择 tools，tools 即后端
MCP server 注册的 33 个 Docker 管理工具（app/mcp/tools.py）。本模块：

- get_mcp_tools_meta()：返回全部工具的元信息（名称/描述/分组/参数），
  供 /admin/agent/tools 接口与前端选择器使用
- build_tools(names)：把选中的工具名包装为 langchain 工具列表，供 agent
  动态绑定。MCP 工具包装为 async StructuredTool，进程内直接调用
  MCPServer.call_tool（无协议开销）；backend/skills 的两个 skill 工具
  （docker_mirror_pull / docker_pull_from_file）直接复用 app.agent.tools

分组与 app/mcp/tools.py 文档一致：容器 11 / 镜像 4 / 网络 2 / 卷 3 / 系统 4 / 项目 9。
"""

import asyncio
from typing import Any, Optional

from pydantic import BaseModel, Field, create_model

from app.agent import tools as skill_tools
from app.mcp.tools import register_all_tools

# backend/skills 下的两个 skill 工具（langchain 工具对象，直接复用）
SKILL_TOOLS: dict[str, Any] = {
    "docker_mirror_pull": skill_tools.docker_mirror_pull,
    "docker_pull_from_file": skill_tools.docker_pull_from_file,
}

# skill 工具的元信息（name/description），与 app/agent/tools.py 的 docstring 一致
SKILL_TOOL_META: list[dict] = [
    {
        "name": "docker_mirror_pull",
        "description": "从国内镜像源拉取单个 Docker 镜像（自动切换镜像源，成功即停止）",
        "group": "镜像拉取",
        "parameters": {
            "image_name": {"type": "string", "required": True, "description": "要拉取的镜像名，可含 tag"},
            "mirror_prefixes": {"type": "array", "required": False, "description": "可选，指定优先尝试的镜像源列表"},
        },
    },
    {
        "name": "docker_pull_from_file",
        "description": "从 Dockerfile 或 docker-compose.yml 提取所有镜像并批量拉取",
        "group": "镜像拉取",
        "parameters": {
            "file_path": {"type": "string", "required": True, "description": "Dockerfile / docker-compose.yml 文件路径"},
        },
    },
]

# MCP 工具分组（与 app/mcp/tools.py 的文档分组一致）
_TOOL_GROUPS: dict[str, list[str]] = {
    "容器": [
        "list_containers", "get_container", "get_container_logs",
        "start_container", "stop_container", "restart_container",
        "kill_container", "pause_container", "unpause_container",
        "remove_container", "run_container",
    ],
    "镜像": ["list_images", "get_image", "pull_image", "remove_image"],
    "网络": ["list_networks", "get_network"],
    "卷": ["list_volumes", "get_volume", "remove_volume"],
    "系统": ["get_system_info", "get_system_usage", "list_stacks", "get_stack_containers"],
    "项目": [
        "list_projects", "get_project", "create_project", "delete_project",
        "get_project_file", "update_project_file", "build_project",
        "project_up", "project_down",
    ],
}

_mcp_server = None
_mcp_tools_meta: Optional[list] = None


def _get_mcp_server():
    """进程内 MCP Server 单例（注册全部 Docker 工具，供 call_tool 调用）。"""
    global _mcp_server
    if _mcp_server is None:
        from mcp.server import MCPServer

        server = MCPServer("shipyard-mcp")
        register_all_tools(server)
        _mcp_server = server
    return _mcp_server


def _collect_tools_meta() -> list[dict]:
    """同步收集全部工具的元信息（名称/描述/参数 schema）。

    不能走 asyncio.run：容器内 supervisor 以 `uvicorn main:app --reload`
    启动，config.load()（import app，触发本函数）发生在事件循环已运行时，
    asyncio.run 会抛 RuntimeError 导致后端启动崩溃（deploy 健康检查 502）。
    MCPServer.list_tools() 是 async，但内部 _tool_manager.list_tools() 为
    同步实现，直接调用即可。
    """
    server = _get_mcp_server()
    tool_manager = getattr(server, "_tool_manager", None)
    if tool_manager is None or not hasattr(tool_manager, "list_tools"):
        # 兜底：mcp SDK 内部结构变化时退回 asyncio.run（非事件循环环境可用）
        return asyncio.run(server.list_tools())
    tools = tool_manager.list_tools()

    group_of = {name: group for group, names in _TOOL_GROUPS.items() for name in names}
    meta = []
    for t in tools:
        properties = (getattr(t, "parameters", None) or {}).get("properties", {})
        required = set((getattr(t, "parameters", None) or {}).get("required", []) or [])
        params = {}
        for pname, pschema in properties.items():
            params[pname] = {
                "type": pschema.get("type", "any"),
                "required": pname in required,
                "description": pschema.get("description", ""),
            }
            if "default" in pschema:
                params[pname]["default"] = pschema["default"]
        meta.append(
            {
                "name": t.name,
                "description": getattr(t, "description", "") or "",
                "group": group_of.get(t.name, "其他"),
                "parameters": params,
            }
        )
    return meta


def get_mcp_tools_meta() -> list[dict]:
    """返回全部 MCP 工具的元信息（惰性收集并缓存，模块首次使用才构建 server）。"""
    global _mcp_tools_meta
    if _mcp_tools_meta is None:
        _mcp_tools_meta = _collect_tools_meta()
    return _mcp_tools_meta


# ---- JSON Schema → pydantic 参数模型 ----


def _map_schema_type(stype: str) -> Any:
    """JSON Schema 类型 → Python 类型。"""
    return {
        "string": str,
        "boolean": bool,
        "integer": int,
        "number": float,
        "array": list,
        "object": dict,
    }.get(stype, Any)


def _schema_to_pydantic(tool_name: str, input_schema: dict) -> type[BaseModel]:
    """将 MCP 工具的 JSON Schema 转换为 pydantic 参数模型。

    - 有 default 的参数 → 使用默认值
    - 出现在 required 中的参数 → 必填
    - 其余参数 → 可选（默认 None）
    """
    properties = (input_schema or {}).get("properties", {}) or {}
    required = set((input_schema or {}).get("required", []) or [])
    fields: dict[str, tuple[Any, Any]] = {}
    for pname, pschema in properties.items():
        ptype = _map_schema_type(pschema.get("type", ""))
        if "default" in pschema:
            fields[pname] = (ptype, Field(default=pschema["default"], description=pschema.get("description", "")))
        elif pname in required:
            fields[pname] = (ptype, Field(description=pschema.get("description", "")))
        else:
            fields[pname] = (Optional[ptype], Field(default=None, description=pschema.get("description", "")))
    return create_model(f"{tool_name}Arguments", **fields)


# ---- 工具调用 ----


def _format_content(content: Any) -> str:
    """将 MCP CallToolResult.content（text 块列表或字符串）转为文本。"""
    if isinstance(content, str):
        return content
    parts = []
    for block in content or []:
        if isinstance(block, dict) and block.get("type") == "text":
            parts.append(block.get("text", ""))
        elif isinstance(block, str):
            parts.append(block)
    return "\n".join(p for p in parts if p)


def _build_mcp_tool(meta: dict):
    """把单个 MCP 工具包装为 langchain async 工具（进程内调用 call_tool）。"""

    name = meta["name"]
    # meta["parameters"] 是元信息格式（required 内嵌在参数内），还原为标准
    # JSON Schema（required 为顶层数组）后转换 pydantic 模型
    properties = {}
    required_names = []
    for pname, pmeta in meta["parameters"].items():
        pschema = {k: v for k, v in pmeta.items() if k != "required"}
        properties[pname] = pschema
        if pmeta.get("required"):
            required_names.append(pname)
    model = _schema_to_pydantic(
        name,
        {"type": "object", "properties": properties, "required": required_names},
    )

    async def _call(**kwargs) -> str:
        server = _get_mcp_server()
        try:
            result = await server.call_tool(name, kwargs)
        except Exception as exc:
            return f"❌ 工具 {name} 执行异常：{exc}"
        if getattr(result, "isError", False):
            return f"❌ 工具 {name} 执行失败：" + _format_content(result.content)
        return _format_content(result.content)

    from langchain_core.tools import StructuredTool

    # async 函数必须通过 coroutine 参数传入，否则 langchain 会以同步方式
    # 调用 async 函数（返回未 await 的 coroutine 对象，调用结果损坏）
    return StructuredTool.from_function(
        func=None,
        coroutine=_call,
        name=name,
        description=meta["description"],
        args_schema=model,
    )


def build_tools(names: list[str]) -> list:
    """按工具名列表构建 langchain 工具（skills + MCP 工具）。

    参数:
        names: 工具名列表；名称可为 skill 工具（docker_mirror_pull /
               docker_pull_from_file）或 MCP 工具。空白项忽略、重复去重。

    异常:
        ValueError: 包含未知工具名时抛出（防静默降级）
    """
    cleaned = [n.strip() for n in names if n and n.strip()]
    cleaned = list(dict.fromkeys(cleaned))  # 去重并保持顺序
    metas = {m["name"]: m for m in get_mcp_tools_meta()}

    result = []
    for name in cleaned:
        if name in SKILL_TOOLS:
            result.append(SKILL_TOOLS[name])
            continue
        meta = metas.get(name)
        if not meta:
            raise ValueError(f"未知工具：{name}")
        result.append(_build_mcp_tool(meta))
    return result
