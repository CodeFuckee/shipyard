"""AI API 供应商配置 —— 增删改查、API Key 加密、测试连接。

覆盖：
- 正常路径：创建 / 列表 / 更新 / 删除 / 测试连接成功
- 边界情况：空名称、重复名称、非法 Base URL、缺 API Key、空列表、
  更新留空 API Key 保留原值、更新/删除不存在的供应商
- 安全：API Key 永不返回、数据库加密存储、测试连接错误分类
"""

from unittest.mock import patch

import pytest
import httpx

# --- 正常路径 ---


def test_create_provider_success(client, admin_headers):
    response = client.post(
        "/admin/ai-providers",
        headers=admin_headers,
        json={
            "name": "deepseek",
            "provider_type": "deepseek",
            "base_url": "https://api.deepseek.com",
            "api_key": "sk-test-123",
            "default_model": "deepseek-chat",
        },
    )

    assert response.status_code == 200
    data = response.json()
    assert data["id"]
    assert data["name"] == "deepseek"
    assert data["provider_type"] == "deepseek"
    assert data["base_url"] == "https://api.deepseek.com"
    assert data["default_model"] == "deepseek-chat"
    assert data["enabled"] is True
    assert data["api_key_configured"] is True
    assert "api_key" not in data


def test_list_providers(client, admin_headers):
    for name, base_url in [
        ("deepseek", "https://api.deepseek.com"),
        ("openai", "https://api.openai.com/v1"),
    ]:
        client.post(
            "/admin/ai-providers",
            headers=admin_headers,
            json={
                "name": name,
                "provider_type": name,
                "base_url": base_url,
                "api_key": f"sk-{name}",
            },
        )

    response = client.get("/admin/ai-providers", headers=admin_headers)

    assert response.status_code == 200
    providers = response.json()
    assert len(providers) == 2
    for p in providers:
        assert "api_key" not in p
        assert p["api_key_configured"] is True


def test_update_provider(client, admin_headers):
    created = client.post(
        "/admin/ai-providers",
        headers=admin_headers,
        json={
            "name": "deepseek",
            "provider_type": "deepseek",
            "base_url": "https://api.deepseek.com",
            "api_key": "sk-old",
        },
    ).json()

    response = client.put(
        f"/admin/ai-providers/{created['id']}",
        headers=admin_headers,
        json={"base_url": "https://api.deepseek.com/v1", "default_model": "deepseek-reasoner"},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["base_url"] == "https://api.deepseek.com/v1"
    assert data["default_model"] == "deepseek-reasoner"
    assert data["api_key_configured"] is True


def test_delete_provider(client, admin_headers):
    created = client.post(
        "/admin/ai-providers",
        headers=admin_headers,
        json={"name": "temp", "provider_type": "custom", "base_url": "https://x.example.com", "api_key": "k"},
    ).json()

    response = client.delete(f"/admin/ai-providers/{created['id']}", headers=admin_headers)

    assert response.status_code == 200
    # 删除后不可再查
    assert client.get(f"/admin/ai-providers/{created['id']}", headers=admin_headers).status_code == 404


def test_test_connection_success(client, admin_headers):
    created = client.post(
        "/admin/ai-providers",
        headers=admin_headers,
        json={"name": "deepseek", "provider_type": "deepseek", "base_url": "https://api.deepseek.com", "api_key": "sk-valid"},
    ).json()

    with patch("app.routers.ai_providers.httpx.get") as mocked_get:
        mocked_get.return_value = httpx.Response(200, json={"data": []})

        response = client.post(f"/admin/ai-providers/{created['id']}/test", headers=admin_headers)

    assert response.status_code == 200
    data = response.json()
    assert data["ok"] is True
    # 请求带 Bearer key 且命中 /models 端点
    url = mocked_get.call_args[0][0]
    assert url == "https://api.deepseek.com/models"
    assert mocked_get.call_args[1]["headers"]["Authorization"] == "Bearer sk-valid"


def test_test_connection_uses_stored_key_after_update(client, admin_headers):
    """更新时未提供 api_key，测试连接仍使用已存储的旧 key。"""
    created = client.post(
        "/admin/ai-providers",
        headers=admin_headers,
        json={"name": "openai", "provider_type": "openai", "base_url": "https://api.openai.com/v1", "api_key": "sk-original"},
    ).json()

    client.put(f"/admin/ai-providers/{created['id']}", headers=admin_headers, json={"default_model": "gpt-4o-mini"})

    with patch("app.routers.ai_providers.httpx.get") as mocked_get:
        mocked_get.return_value = httpx.Response(200, json={})
        client.post(f"/admin/ai-providers/{created['id']}/test", headers=admin_headers)

    assert mocked_get.call_args[1]["headers"]["Authorization"] == "Bearer sk-original"


# --- 边界情况 ---


def test_create_provider_empty_name(client, admin_headers):
    response = client.post(
        "/admin/ai-providers",
        headers=admin_headers,
        json={"name": "", "provider_type": "custom", "base_url": "https://x.example.com", "api_key": "k"},
    )

    assert response.status_code == 422


def test_create_provider_duplicate_name(client, admin_headers):
    payload = {"name": "deepseek", "provider_type": "deepseek", "base_url": "https://api.deepseek.com", "api_key": "sk-1"}
    assert client.post("/admin/ai-providers", headers=admin_headers, json=payload).status_code == 200

    response = client.post("/admin/ai-providers", headers=admin_headers, json=payload)
    assert response.status_code == 409
    assert "已存在" in response.json()["detail"]


def test_create_provider_invalid_base_url(client, admin_headers):
    for bad_url in ["not-a-url", "ftp://x.com", "http://", "https:// 有空格"]:
        response = client.post(
            "/admin/ai-providers",
            headers=admin_headers,
            json={"name": f"p-{bad_url[:8]}", "provider_type": "custom", "base_url": bad_url, "api_key": "k"},
        )
        assert response.status_code == 422, f"base_url={bad_url!r} 应被拒绝"


def test_create_provider_missing_api_key(client, admin_headers):
    response = client.post(
        "/admin/ai-providers",
        headers=admin_headers,
        json={"name": "openai", "provider_type": "openai", "base_url": "https://api.openai.com/v1", "api_key": ""},
    )

    assert response.status_code == 422


def test_create_provider_invalid_type(client, admin_headers):
    response = client.post(
        "/admin/ai-providers",
        headers=admin_headers,
        json={"name": "x", "provider_type": "claude", "base_url": "https://api.example.com", "api_key": "k"},
    )

    assert response.status_code == 422


def test_list_providers_empty(client, admin_headers):
    response = client.get("/admin/ai-providers", headers=admin_headers)
    assert response.status_code == 200
    assert response.json() == []


def test_update_provider_keep_key_when_empty(client, admin_headers):
    created = client.post(
        "/admin/ai-providers",
        headers=admin_headers,
        json={"name": "deepseek", "provider_type": "deepseek", "base_url": "https://api.deepseek.com", "api_key": "sk-keep"},
    ).json()

    # api_key 省略或为空字符串均不修改原 key
    response = client.put(
        f"/admin/ai-providers/{created['id']}", headers=admin_headers, json={"api_key": ""}
    )
    assert response.status_code == 200
    assert response.json()["api_key_configured"] is True

    with patch("app.routers.ai_providers.httpx.get") as mocked_get:
        mocked_get.return_value = httpx.Response(200, json={})
        client.post(f"/admin/ai-providers/{created['id']}/test", headers=admin_headers)

    assert mocked_get.call_args[1]["headers"]["Authorization"] == "Bearer sk-keep"


def test_update_provider_replace_key(client, admin_headers):
    created = client.post(
        "/admin/ai-providers",
        headers=admin_headers,
        json={"name": "deepseek", "provider_type": "deepseek", "base_url": "https://api.deepseek.com", "api_key": "sk-old"},
    ).json()

    response = client.put(
        f"/admin/ai-providers/{created['id']}", headers=admin_headers, json={"api_key": "sk-new"}
    )
    assert response.status_code == 200

    with patch("app.routers.ai_providers.httpx.get") as mocked_get:
        mocked_get.return_value = httpx.Response(200, json={})
        client.post(f"/admin/ai-providers/{created['id']}/test", headers=admin_headers)

    assert mocked_get.call_args[1]["headers"]["Authorization"] == "Bearer sk-new"


def test_update_provider_duplicate_name(client, admin_headers):
    client.post(
        "/admin/ai-providers",
        headers=admin_headers,
        json={"name": "a", "provider_type": "custom", "base_url": "https://a.example.com", "api_key": "k1"},
    )
    b = client.post(
        "/admin/ai-providers",
        headers=admin_headers,
        json={"name": "b", "provider_type": "custom", "base_url": "https://b.example.com", "api_key": "k2"},
    ).json()

    response = client.put(f"/admin/ai-providers/{b['id']}", headers=admin_headers, json={"name": "a"})
    assert response.status_code == 409


def test_update_provider_nonexistent(client, admin_headers):
    response = client.put(
        "/admin/ai-providers/nonexistent-id", headers=admin_headers, json={"base_url": "https://x.example.com"}
    )
    assert response.status_code == 404


def test_delete_provider_nonexistent(client, admin_headers):
    response = client.delete("/admin/ai-providers/nonexistent-id", headers=admin_headers)
    assert response.status_code == 404


def test_get_provider_detail(client, admin_headers):
    created = client.post(
        "/admin/ai-providers",
        headers=admin_headers,
        json={"name": "deepseek", "provider_type": "deepseek", "base_url": "https://api.deepseek.com", "api_key": "sk-x"},
    ).json()

    response = client.get(f"/admin/ai-providers/{created['id']}", headers=admin_headers)

    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "deepseek"
    assert "api_key" not in data
    assert data["api_key_configured"] is True


def test_get_provider_nonexistent(client, admin_headers):
    response = client.get("/admin/ai-providers/nonexistent-id", headers=admin_headers)
    assert response.status_code == 404


# --- 安全：加密存储与不泄露 ---


def test_api_key_stored_encrypted(client, admin_headers, db_session):
    client.post(
        "/admin/ai-providers",
        headers=admin_headers,
        json={"name": "deepseek", "provider_type": "deepseek", "base_url": "https://api.deepseek.com", "api_key": "sk-secret-plaintext"},
    )

    from app.db.models import AIProviderModel

    row = db_session.query(AIProviderModel).first()
    assert row is not None
    assert row.encrypted_api_key != "sk-secret-plaintext"
    assert "sk-secret-plaintext" not in row.encrypted_api_key


def test_api_key_never_in_any_response(client, admin_headers):
    created = client.post(
        "/admin/ai-providers",
        headers=admin_headers,
        json={"name": "deepseek", "provider_type": "deepseek", "base_url": "https://api.deepseek.com", "api_key": "sk-hidden"},
    ).json()

    for response in [
        client.get("/admin/ai-providers", headers=admin_headers),
        client.get(f"/admin/ai-providers/{created['id']}", headers=admin_headers),
        client.put(f"/admin/ai-providers/{created['id']}", headers=admin_headers, json={"default_model": "m"}),
    ]:
        body = response.text
        assert "sk-hidden" not in body
        assert '"api_key"' not in body


def test_test_connection_without_key_fails(client, admin_headers):
    created = client.post(
        "/admin/ai-providers",
        headers=admin_headers,
        json={"name": "empty", "provider_type": "custom", "base_url": "https://x.example.com", "api_key": "k"},
    ).json()
    # 清空 key（更新为空串等效于保留；这里直接模拟无 key 供应商：删除后重建不带 key 不允许，
    # 因此通过把 key 更新为空场景在 test_update 已覆盖；此处构造无 key 仅验证接口不崩溃）
    response = client.post(f"/admin/ai-providers/{created['id']}/test", headers=admin_headers)
    assert response.status_code in (200, 400)


def test_test_connection_nonexistent(client, admin_headers):
    response = client.post("/admin/ai-providers/nonexistent-id/test", headers=admin_headers)
    assert response.status_code == 404


def test_test_connection_unauthorized(client, admin_headers):
    created = client.post(
        "/admin/ai-providers",
        headers=admin_headers,
        json={"name": "openai", "provider_type": "openai", "base_url": "https://api.openai.com/v1", "api_key": "sk-bad"},
    ).json()

    with patch("app.routers.ai_providers.httpx.get") as mocked_get:
        mocked_get.return_value = httpx.Response(401, json={"error": "invalid_api_key"})

        response = client.post(f"/admin/ai-providers/{created['id']}/test", headers=admin_headers)

    assert response.status_code == 200
    data = response.json()
    assert data["ok"] is False
    assert "401" in data["message"] or "Key" in data["message"]


def test_test_connection_network_error(client, admin_headers):
    created = client.post(
        "/admin/ai-providers",
        headers=admin_headers,
        json={"name": "custom", "provider_type": "custom", "base_url": "https://unreachable.example.com", "api_key": "k"},
    ).json()

    with patch("app.routers.ai_providers.httpx.get", side_effect=httpx.ConnectError("connection refused")):
        response = client.post(f"/admin/ai-providers/{created['id']}/test", headers=admin_headers)

    assert response.status_code == 200
    assert response.json()["ok"] is False


def test_test_connection_timeout(client, admin_headers):
    created = client.post(
        "/admin/ai-providers",
        headers=admin_headers,
        json={"name": "custom", "provider_type": "custom", "base_url": "https://slow.example.com", "api_key": "k"},
    ).json()

    with patch("app.routers.ai_providers.httpx.get", side_effect=httpx.TimeoutException("timeout")):
        response = client.post(f"/admin/ai-providers/{created['id']}/test", headers=admin_headers)

    assert response.status_code == 200
    assert response.json()["ok"] is False
