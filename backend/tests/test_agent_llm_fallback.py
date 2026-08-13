"""Agent LLM 回退 — hermes 未配置时回退 ai_providers 默认供应商（issue #21 第四轮）。

覆盖：
- resolve_llm_config：hermes 优先；回退默认供应商（is_default=1、enabled、有 Key）；
  默认被禁用跳过；无默认标记回退第一个可用；无 Key / 禁用跳过；
  都不可用抛 LLMNotConfiguredError
- /admin/ai-providers is_default：设默认清除其他默认；取消默认；创建带默认；
  列表序列化含 is_default
- agent 路由集成：hermes 未配置 + 默认供应商 → 聊天正常（llm_config 传入）；
  都未配置 → 503 llm_not_configured；/status 反映 LLM 来源
- 本机执行约束：回退路径下 agent 绑定的工具仍为服务器本机执行器
  （docker unix socket + 进程内 MCP，工具构建逻辑不因 LLM 来源变化）
"""

import pytest

from app.agent import service
from app.core.crypto import encrypt
from app.db.models import AIProviderModel
from app.services import hermes_client


@pytest.fixture(autouse=True)
def hermes_env(monkeypatch):
    """默认配置一个可用的 hermes 实例（各用例按需置空模拟未配置）。"""
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "https://hermes.example.com/v1")
    monkeypatch.setattr(hermes_client, "HERMES_API_KEY", "sk-hermes-test")
    monkeypatch.setattr(hermes_client, "HERMES_MODEL", "hermes-chat")


def _create_provider(
    db,
    name="deepseek",
    provider_type="deepseek",
    base_url="https://api.deepseek.com",
    api_key="sk-test-123",
    default_model="deepseek-chat",
    enabled=1,
    is_default=0,
):
    """创建供应商记录；api_key=None 表示无 Key。"""
    provider = AIProviderModel(
        name=name,
        provider_type=provider_type,
        base_url=base_url,
        encrypted_api_key=encrypt(api_key) if api_key else None,
        default_model=default_model,
        enabled=enabled,
        is_default=is_default,
    )
    db.add(provider)
    db.commit()
    db.refresh(provider)
    return provider


def _disable_hermes(monkeypatch):
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "")


# --- resolve_llm_config ---


def test_resolve_uses_hermes_when_configured(db_session):
    config = service.resolve_llm_config(db_session)
    assert config["source"] == "hermes"
    assert config["base_url"] == "https://hermes.example.com/v1"
    assert config["api_key"] == "sk-hermes-test"
    assert config["model"] == "hermes-chat"


def test_resolve_falls_back_to_default_provider(db_session, monkeypatch):
    _disable_hermes(monkeypatch)
    _create_provider(db_session, is_default=1)

    config = service.resolve_llm_config(db_session)
    assert config["source"] == "provider"
    assert config["base_url"] == "https://api.deepseek.com"
    assert config["api_key"] == "sk-test-123"  # 已解密
    assert config["model"] == "deepseek-chat"
    assert config["name"] == "deepseek"


def test_resolve_prefers_default_over_created_order(db_session, monkeypatch):
    """默认标记优先于创建顺序：先创建的 A 无默认、后创建的 B 为默认 → 选 B。"""
    _disable_hermes(monkeypatch)
    _create_provider(db_session, name="first", is_default=0)
    _create_provider(db_session, name="second", is_default=1)

    config = service.resolve_llm_config(db_session)
    assert config["name"] == "second"


def test_resolve_skips_disabled_default_provider(db_session, monkeypatch):
    """默认供应商被禁用时跳过，回退第一个可用供应商。"""
    _disable_hermes(monkeypatch)
    _create_provider(db_session, name="disabled-default", is_default=1, enabled=0)
    _create_provider(db_session, name="usable")

    config = service.resolve_llm_config(db_session)
    assert config["name"] == "usable"


def test_resolve_skips_provider_without_key(db_session, monkeypatch):
    """默认供应商未配置 API Key 时跳过，回退第一个可用供应商。"""
    _disable_hermes(monkeypatch)
    _create_provider(db_session, name="no-key-default", api_key=None, is_default=1)
    _create_provider(db_session, name="with-key")

    config = service.resolve_llm_config(db_session)
    assert config["name"] == "with-key"


def test_resolve_no_default_uses_first_enabled(db_session, monkeypatch):
    """无默认标记时按创建顺序取第一个 enabled 且有 Key 的。"""
    _disable_hermes(monkeypatch)
    _create_provider(db_session, name="first")
    _create_provider(db_session, name="second")

    config = service.resolve_llm_config(db_session)
    assert config["name"] == "first"


def test_resolve_skips_disabled_provider(db_session, monkeypatch):
    """无默认标记时，禁用的供应商也要跳过。"""
    _disable_hermes(monkeypatch)
    _create_provider(db_session, name="disabled", enabled=0)
    _create_provider(db_session, name="usable")

    config = service.resolve_llm_config(db_session)
    assert config["name"] == "usable"


def test_resolve_raises_when_nothing_configured(db_session, monkeypatch):
    """hermes 未配置且无任何可用供应商 → LLMNotConfiguredError。"""
    _disable_hermes(monkeypatch)
    _create_provider(db_session, name="disabled", enabled=0)
    _create_provider(db_session, name="no-key", api_key=None)

    with pytest.raises(service.LLMNotConfiguredError):
        service.resolve_llm_config(db_session)


def test_resolve_without_db_raises_when_hermes_disabled(monkeypatch):
    """无 db 且 hermes 未配置 → LLMNotConfiguredError（build_agent 缺省路径）。"""
    _disable_hermes(monkeypatch)
    with pytest.raises(service.LLMNotConfiguredError):
        service.resolve_llm_config(None)


# --- /admin/ai-providers is_default ---


def _create_via_api(client, admin_headers, name, is_default=False):
    return client.post(
        "/admin/ai-providers",
        headers=admin_headers,
        json={
            "name": name,
            "provider_type": "custom",
            "base_url": f"https://{name}.example.com",
            "api_key": f"sk-{name}",
            "is_default": is_default,
        },
    ).json()


def test_create_provider_with_default_clears_others(client, admin_headers):
    first = _create_via_api(client, admin_headers, "first", is_default=True)
    second = _create_via_api(client, admin_headers, "second", is_default=True)

    providers = client.get("/admin/ai-providers", headers=admin_headers).json()
    by_id = {p["id"]: p for p in providers}
    assert by_id[second["id"]]["is_default"] is True
    assert by_id[first["id"]]["is_default"] is False  # 唯一默认


def test_update_provider_set_default_clears_others(client, admin_headers):
    first = _create_via_api(client, admin_headers, "first")
    second = _create_via_api(client, admin_headers, "second")

    client.put(
        f"/admin/ai-providers/{first['id']}",
        headers=admin_headers,
        json={"is_default": True},
    )
    providers = client.get("/admin/ai-providers", headers=admin_headers).json()
    by_id = {p["id"]: p for p in providers}
    assert by_id[first["id"]]["is_default"] is True
    assert by_id[second["id"]]["is_default"] is False

    # 切换默认到 second
    client.put(
        f"/admin/ai-providers/{second['id']}",
        headers=admin_headers,
        json={"is_default": True},
    )
    providers = client.get("/admin/ai-providers", headers=admin_headers).json()
    by_id = {p["id"]: p for p in providers}
    assert by_id[second["id"]]["is_default"] is True
    assert by_id[first["id"]]["is_default"] is False


def test_update_provider_unset_default(client, admin_headers):
    provider = _create_via_api(client, admin_headers, "first", is_default=True)
    response = client.put(
        f"/admin/ai-providers/{provider['id']}",
        headers=admin_headers,
        json={"is_default": False},
    )
    assert response.status_code == 200
    assert response.json()["is_default"] is False

    providers = client.get("/admin/ai-providers", headers=admin_headers).json()
    assert all(p["is_default"] is False for p in providers)


def test_provider_list_includes_is_default(client, admin_headers):
    _create_via_api(client, admin_headers, "plain")
    data = client.get("/admin/ai-providers", headers=admin_headers).json()
    assert data and "is_default" in data[0]
    assert data[0]["is_default"] is False


# --- agent 路由集成 ---


def test_chat_stream_falls_back_to_provider(client, admin_headers, db_session, monkeypatch):
    """hermes 未配置 + 默认供应商 → 流式对话正常，llm_config 为 provider 源。"""
    _disable_hermes(monkeypatch)
    _create_provider(db_session, is_default=1)
    received = {}

    async def fake_stream_agent(messages, tools_names=None, max_iterations=None, llm_config=None):
        received["llm_config"] = llm_config
        yield {"type": "done"}

    monkeypatch.setattr(service, "stream_agent", fake_stream_agent)
    response = client.post(
        "/admin/agent/chat/stream",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "hi"}]},
    )
    assert response.status_code == 200
    assert received["llm_config"]["source"] == "provider"
    assert received["llm_config"]["base_url"] == "https://api.deepseek.com"


def test_chat_falls_back_to_provider(client, admin_headers, db_session, monkeypatch):
    """非流式对话同样回退默认供应商。"""
    _disable_hermes(monkeypatch)
    _create_provider(db_session, is_default=1)
    received = {}

    def fake_run_agent(messages, max_iterations=None, llm_config=None):
        received["llm_config"] = llm_config
        return {"reply": "ok", "steps": []}

    monkeypatch.setattr(service, "run_agent", fake_run_agent)
    response = client.post(
        "/admin/agent/chat",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "hi"}]},
    )
    assert response.status_code == 200
    assert received["llm_config"]["source"] == "provider"


def test_stream_503_detail_mentions_both_options(client, admin_headers, monkeypatch):
    """两者都未配置时 503 的 detail 应提及两种配置入口（引导双入口弹窗）。"""
    _disable_hermes(monkeypatch)
    response = client.post(
        "/admin/agent/chat/stream",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "hi"}]},
    )
    assert response.status_code == 503
    body = response.json()
    assert body["error_code"] == "llm_not_configured"
    assert "Hermes" in body["detail"]
    assert "供应商" in body["detail"]


def test_status_reflects_provider_fallback(client, admin_headers, db_session, monkeypatch):
    """/status 反映回退后的实际 LLM 来源。"""
    _disable_hermes(monkeypatch)
    _create_provider(db_session, is_default=1)

    response = client.get("/admin/agent/status", headers=admin_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["enabled"] is False  # hermes 本身仍未启用
    assert data["llm_source"] == "provider"
    assert data["llm_name"] == "deepseek"


def test_status_reflects_hermes_source(client, admin_headers):
    response = client.get("/admin/agent/status", headers=admin_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["llm_source"] == "hermes"


# --- 回退路径的 agent 构建与本机执行约束 ---


class _FakeLLM:
    """记录构建参数的假 ChatOpenAI。"""

    def __init__(self, **kwargs):
        self.kwargs = kwargs


def test_build_agent_with_fallback_config_uses_provider_llm(db_session, monkeypatch):
    """build_agent(llm_config=provider) 时 ChatOpenAI 使用供应商配置。"""
    _disable_hermes(monkeypatch)
    _create_provider(db_session, is_default=1)
    config = service.resolve_llm_config(db_session)
    captured = {}

    def fake_chat_openai(**kwargs):
        captured.update(kwargs)
        return _FakeLLM(**kwargs)

    def fake_create_agent(llm, tools, system_prompt=None, **kwargs):
        return {"llm": llm, "tools": tools}

    monkeypatch.setattr("langchain_openai.ChatOpenAI", fake_chat_openai)
    monkeypatch.setattr("langchain.agents.create_agent", fake_create_agent)

    agent = service.build_agent(llm_config=config)
    assert captured["base_url"] == "https://api.deepseek.com"
    assert captured["api_key"] == "sk-test-123"
    assert captured["model"] == "deepseek-chat"
    assert isinstance(agent["llm"], _FakeLLM)


def test_fallback_agent_binds_local_executor_tools(db_session, monkeypatch):
    """回退路径下绑定的工具与 hermes 路径完全一致（服务器本机执行器：
    docker unix socket + 进程内 MCP call_tool），不因 LLM 来源变化。"""
    _disable_hermes(monkeypatch)
    _create_provider(db_session, is_default=1)
    config = service.resolve_llm_config(db_session)
    captured = {}

    def fake_chat_openai(**kwargs):
        return _FakeLLM(**kwargs)

    def fake_create_agent(llm, tools, system_prompt=None, **kwargs):
        captured["tool_names"] = [getattr(t, "name", None) for t in tools]
        return {"llm": llm, "tools": tools}

    monkeypatch.setattr("langchain_openai.ChatOpenAI", fake_chat_openai)
    monkeypatch.setattr("langchain.agents.create_agent", fake_create_agent)

    service.build_agent(llm_config=config, tools_names=["docker_mirror_pull", "list_containers"])
    # skill 工具（DockerSocketPuller）与 MCP 工具（进程内 MCPServer）均绑定
    assert "docker_mirror_pull" in captured["tool_names"]
    assert "list_containers" in captured["tool_names"]
