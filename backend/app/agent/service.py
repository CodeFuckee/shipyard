"""镜像拉取 Agent — 基于 langchain + langgraph 的工具调用 Agent。

Agent 使用 hermes（OpenAI 兼容接口）作为 LLM，绑定 backend/skills 的两个
skill 工具（docker_mirror_pull / docker_pull_from_file），用户以自然语言
下达拉取指令，Agent 自动规划并调用工具完成镜像拉取。

LLM 配置复用 hermes 接入（app/services/hermes_client.py）：
- base_url / api_key / model 与 hermes 一致（数据库保存值优先于环境变量）
- model 未配置时自动探测 {base}/models 的第一个可用模型
"""

import json
from typing import Any, List, Optional

import httpx

from app.agent import tools
from app.core.config import AGENT_MAX_ITERATIONS
from app.services import hermes_client
from app.services.hermes_client import HermesError, HermesNotConfiguredError

_SYSTEM_PROMPT = """你是 Docker 镜像拉取助手。使用提供的两个工具帮用户拉取 Docker 镜像：
1. docker_mirror_pull：拉取单个镜像（自动切换国内镜像源，成功即停止）
2. docker_pull_from_file：从 Dockerfile / docker-compose.yml 批量拉取镜像
用户要求拉取镜像时，直接调用对应工具执行；拉取过程与结果以中文汇报。"""


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


def build_agent(model: Optional[str] = None) -> Any:
    """构建 langchain agent（绑定两个 skill 工具）。

    未配置 hermes 时抛 HermesNotConfiguredError；model 未指定时自动探测。
    """
    status = hermes_client.hermes_status()
    if not status["enabled"]:
        raise HermesNotConfiguredError()
    api_key = hermes_client.effective_api_key()
    resolved_model = _resolve_model(status["base_url"], api_key, model or status["model"])

    from langchain.agents import create_agent
    from langchain_openai import ChatOpenAI

    llm = ChatOpenAI(
        base_url=status["base_url"],
        api_key=api_key or "not-needed",
        model=resolved_model,
        temperature=0.3,
        timeout=90,
    )
    return create_agent(
        llm,
        [tools.docker_mirror_pull, tools.docker_pull_from_file],
        system_prompt=_SYSTEM_PROMPT,
    )


def _content_text(content: Any) -> str:
    """将消息 content（str 或内容块列表）转为文本。"""
    if isinstance(content, str):
        return content
    return json.dumps(content, ensure_ascii=False)


def run_agent(messages: List[dict], max_iterations: Optional[int] = None) -> dict:
    """运行 agent 完成一轮对话，返回最终回复与工具执行步骤。

    返回: {"reply": str, "steps": [{"role", "content"}, ...]}
    """
    agent = build_agent()
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
