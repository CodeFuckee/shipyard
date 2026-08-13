"""镜像拉取 Agent — 基于 langchain + langgraph 的工具调用 Agent。

Agent 使用 hermes（OpenAI 兼容接口）作为 LLM，绑定 backend/skills 的两个
skill 工具（docker_mirror_pull / docker_pull_from_file），用户以自然语言
下达拉取指令，Agent 自动规划并调用工具完成镜像拉取。

LLM 配置来源（issue #21 第四轮）：
1. hermes 接入（app/services/hermes_client.py，数据库保存值优先于环境变量）
2. hermes 未配置时回退 ai_providers 默认供应商（is_default=1 且启用且已配置
   API Key；无默认标记时按创建顺序取第一个可用）—— 两者都不可用时抛
   LLMNotConfiguredError
工具执行始终在服务器本机：skill 工具走 docker unix socket，MCP 工具走
进程内 MCPServer.call_tool，不因 LLM 来源变化。
"""

import json
from typing import Any, List, Optional

import httpx

from app.agent import mcp_tools, tools
from app.core.config import AGENT_MAX_ITERATIONS
from app.services import hermes_client
from app.services.hermes_client import HermesError, HermesNotConfiguredError

_SYSTEM_PROMPT = """你是 Docker 镜像拉取助手。使用提供的两个工具帮用户拉取 Docker 镜像：
1. docker_mirror_pull：拉取单个镜像（自动切换国内镜像源，成功即停止）
2. docker_pull_from_file：从 Dockerfile / docker-compose.yml 批量拉取镜像
用户要求拉取镜像时，直接调用对应工具执行；拉取过程与结果以中文汇报。"""

_GENERAL_SYSTEM_PROMPT = """你是 Docker 容器管理助手。你可以使用提供的工具直接管理 Docker 资源：
容器（列出/启停/重启/删除/日志）、镜像（列出/拉取/删除）、网络、卷、
Docker Compose 项目（创建/构建/启停）以及从国内镜像源拉取镜像。
用户下达管理指令时，先判断需要哪些工具，依次调用执行；执行过程与结果以中文汇报。
涉及删除、强制操作（kill/force/删除卷）时，先向用户确认再执行，不得擅自破坏数据。"""

# 可用工具名全集：skills（backend/skills 两个）+ MCP Docker 工具（33 个）
SKILL_TOOL_NAMES = ["docker_mirror_pull", "docker_pull_from_file"]
MCP_TOOL_NAMES = {t["name"] for t in mcp_tools.get_mcp_tools_meta()}


class LLMNotConfiguredError(HermesError):
    """hermes 与 AI 供应商均未配置（issue #21 第四轮）。

    前端按 error_code=llm_not_configured 弹出双入口引导
    （配置 Hermes / 配置 AI 供应商）。
    """

    def __init__(self):
        super().__init__(
            "LLM 未配置：请配置 Hermes 接入，或在 AI 供应商中添加启用且含 API Key 的供应商",
            status_code=503,
        )


def resolve_llm_config(db=None) -> dict:
    """确定 agent 使用的 LLM 配置（issue #21 第四轮）。

    优先级：
    1. hermes 接入已启用 → hermes（数据库运行时配置/环境变量）
    2. ai_providers 默认供应商：is_default=1、启用、已配置 API Key；
       无默认标记时按创建顺序取第一个启用且有 Key 的
    3. 两者都不可用 → 抛 LLMNotConfiguredError

    参数:
        db: SQLAlchemy 会话（查询 ai_providers 用）；None 时仅判断 hermes

    返回:
        {"source": "hermes"|"provider", "name": str, "base_url": str,
         "api_key": str, "model": str}
    """
    status = hermes_client.hermes_status()
    if status["enabled"]:
        return {
            "source": "hermes",
            "name": "Hermes",
            "base_url": status["base_url"],
            "api_key": hermes_client.effective_api_key(),
            "model": status["model"],
        }

    if db is not None:
        from app.core.crypto import decrypt
        from app.db.models import AIProviderModel

        provider = (
            db.query(AIProviderModel)
            .filter(
                AIProviderModel.enabled == 1,
                AIProviderModel.encrypted_api_key.isnot(None),
                AIProviderModel.encrypted_api_key != "",
            )
            .order_by(
                AIProviderModel.is_default.desc(), AIProviderModel.created_at.asc()
            )
            .first()
        )
        if provider is not None:
            return {
                "source": "provider",
                "name": provider.name,
                "base_url": provider.base_url,
                "api_key": decrypt(provider.encrypted_api_key),
                "model": provider.default_model or "",
            }

    raise LLMNotConfiguredError()


def _resolve_model(base_url: str, api_key: str, configured_model: str) -> str:
    """确定使用的模型：显式配置优先，否则探测 /models 的第一个可用模型。"""
    if configured_model.strip():
        return configured_model.strip()

    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    try:
        with httpx.Client(timeout=15.0) as client:
            response = client.get(f"{base_url.rstrip('/')}/models", headers=headers)
    except (httpx.TimeoutException, httpx.HTTPError) as exc:
        raise HermesError(f"未配置模型且探测 /models 失败: {exc}") from None
    if response.status_code != 200:
        raise HermesError(f"未配置模型且探测 /models 失败（HTTP {response.status_code}）")

    data = response.json()
    models = (data.get("data") or []) if isinstance(data, dict) else []
    model_ids = [m.get("id") for m in models if isinstance(m, dict) and m.get("id")]
    if not model_ids:
        raise HermesError("未配置模型且 /models 未返回任何模型，请在 hermes 设置中配置模型")
    return model_ids[0]


def _build_system_prompt(tools_names: List[str]) -> str:
    """根据启用的工具生成系统提示：启用 MCP Docker 工具 → 通用管理助手；
    仅 skill 工具 → 保持原有的镜像拉取助手提示。"""
    if any(name in MCP_TOOL_NAMES for name in tools_names):
        return _GENERAL_SYSTEM_PROMPT
    return _SYSTEM_PROMPT


def build_agent(
    model: Optional[str] = None,
    tools_names: Optional[List[str]] = None,
    system_prompt: Optional[str] = None,
    llm_config: Optional[dict] = None,
) -> Any:
    """构建 langchain agent，工具集可动态指定。

    参数:
        model: LLM 模型名，缺省时自动探测
        tools_names: 工具名列表（skill + MCP 工具），None = 默认两个 skill 工具
        system_prompt: 自定义系统提示，缺省时按工具集自动生成
        llm_config: LLM 配置（resolve_llm_config 的结果）；None = 自动解析
            （hermes → ai_providers 默认供应商），都不可用抛
            LLMNotConfiguredError

    工具始终为服务器本机执行器（docker unix socket / 进程内 MCP），
    与 LLM 来源无关。model 未指定时自动探测。
    """
    config = llm_config or resolve_llm_config()
    api_key = config["api_key"]
    resolved_model = _resolve_model(config["base_url"], api_key, model or config["model"])

    from langchain.agents import create_agent
    from langchain_openai import ChatOpenAI

    names = tools_names if tools_names is not None else SKILL_TOOL_NAMES
    tool_objs = mcp_tools.build_tools(names)

    llm = ChatOpenAI(
        base_url=config["base_url"],
        api_key=api_key or "not-needed",
        model=resolved_model,
        temperature=0.3,
        timeout=90,
    )
    return create_agent(
        llm,
        tool_objs,
        system_prompt=system_prompt or _build_system_prompt(names),
        name="agent",
    )


def _content_text(content: Any) -> str:
    """将消息 content（str 或内容块列表）转为文本。"""
    if isinstance(content, str):
        return content
    return json.dumps(content, ensure_ascii=False)


def run_agent(
    messages: List[dict],
    max_iterations: Optional[int] = None,
    llm_config: Optional[dict] = None,
) -> dict:
    """运行 agent 完成一轮对话，返回最终回复与工具执行步骤。

    返回: {"reply": str, "steps": [{"role", "content"}, ...]}
    """
    agent = build_agent(llm_config=llm_config)
    iterations = max_iterations or AGENT_MAX_ITERATIONS
    result = agent.invoke(
        {"messages": messages},
        config={"recursion_limit": iterations * 2 + 20},
    )

    reply_messages = result.get("messages") or []
    final = reply_messages[-1] if reply_messages else None
    reply = _content_text(getattr(final, "content", "")) if final is not None else ""

    steps = []
    for msg in reply_messages:
        role = getattr(msg, "type", "")
        if role in ("ai", "tool"):
            steps.append({"role": role, "content": _content_text(getattr(msg, "content", ""))})
    return {"reply": reply, "steps": steps}


async def stream_agent(
    messages: List[dict],
    tools_names: Optional[List[str]] = None,
    max_iterations: Optional[int] = None,
    llm_config: Optional[dict] = None,
):
    """流式运行 agent（async 生成器），逐段产出事件 dict。

    事件类型:
        {"type": "token", "content": str}      — LLM 回复的 token 增量（打字机效果）
        {"type": "step", "name", "arguments"}  — 工具调用开始
        {"type": "step_result", "name", "result"} — 工具调用结束
        {"type": "reply", "content": str}       — 最终完整回复
        {"type": "done"}                        — 正常结束
        {"type": "error", "message": str}       — 构建/执行错误（流内终止）

    llm_config 缺省时自动解析（hermes → ai_providers 默认供应商）。
    基于 agent.astream_events(v2)：on_chat_model_stream → token，
    on_tool_start/on_tool_end → step 步骤，on_chain_end → 最终回复兜底。
    """
    try:
        agent = build_agent(tools_names=tools_names, llm_config=llm_config)
    except (HermesNotConfiguredError, HermesError) as exc:
        yield {"type": "error", "message": exc.message}
        return

    iterations = max_iterations or AGENT_MAX_ITERATIONS
    final_reply = ""
    try:
        async for event in agent.astream_events(
            {"messages": messages},
            version="v2",
            config={"recursion_limit": iterations * 2 + 20},
        ):
            kind = event.get("event")
            if kind == "on_chat_model_stream":
                chunk = event.get("data", {}).get("chunk")
                content = getattr(chunk, "content", None)
                # 过滤空 token（如工具调用时无文本的 chunk）
                if isinstance(content, str) and content:
                    yield {"type": "token", "content": content}
            elif kind == "on_tool_start":
                yield {
                    "type": "step",
                    "name": event.get("name", ""),
                    "arguments": event.get("data", {}).get("input", {}),
                }
            elif kind == "on_tool_end":
                output = event.get("data", {}).get("output")
                yield {
                    "type": "step_result",
                    "name": event.get("name", ""),
                    "result": output if isinstance(output, str) else _content_text(output),
                }
            elif kind == "on_chain_end" and event.get("name") == "agent":
                # 最终回复兜底：agent 图结束时取最终消息
                output = event.get("data", {}).get("output") or {}
                msgs = output.get("messages") or []
                if msgs:
                    final_reply = _content_text(getattr(msgs[-1], "content", ""))
    except Exception as exc:
        yield {"type": "error", "message": f"Agent 执行异常：{exc}"}
        return

    yield {"type": "reply", "content": final_reply}
    yield {"type": "done"}
