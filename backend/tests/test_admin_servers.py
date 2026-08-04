"""复现测试：Web 端服务器列表跨 origin 不共享。

背景：服务器列表存储在前端 localStorage，而 localStorage 按 origin（协议+主机+端口）
隔离，因此从 http://10.0.0.169:8080 添加的服务器在 https://home.chenkaidi.top:507
（同一后端实例）不可见。修复方向：服务器列表存入后端数据库，同一实例的所有
访问入口（origin）共享同一份数据。

本测试验证后端 /admin/servers 接口不存在时即为复现（404 / 401），
修复后应支持完整的保存、读取、加密存储能力。
"""

import json
import uuid


class TestAdminServers:
    def test_get_servers_requires_auth(self, client):
        """未认证时获取服务器列表应返回 401。"""
        response = client.get("/admin/servers")
        assert response.status_code == 401

    def test_get_servers_empty(self, client, admin_headers):
        """初始时服务器列表应为空。"""
        response = client.get("/admin/servers", headers=admin_headers)
        assert response.status_code == 200
        assert response.json() == []

    def test_save_and_load_servers(self, client, admin_headers):
        """保存服务器列表后应能完整读回（跨 origin 共享的基础）。

        模拟前端从 origin A 保存、从 origin B 读取：两者访问同一后端实例，
        必须读到同一份数据。
        """
        payload = [
            {
                "name": "Home Server",
                "url": "http://10.0.0.169:9000",
                "apiKey": "key-1",
                "ignoreSsl": "false",
            },
            {
                "name": "Work Server",
                "url": "https://server-b:8000",
                "apiKey": "key-2",
                "ignoreSsl": "true",
            },
        ]

        # origin A 保存
        response = client.put("/admin/servers", headers=admin_headers, json=payload)
        assert response.status_code == 200

        # origin B（同一实例）读取
        response = client.get("/admin/servers", headers=admin_headers)
        assert response.status_code == 200
        data = response.json()
        assert data == payload

    def test_api_key_encrypted_at_rest(self, client, admin_headers, db_session):
        """数据库中的 apiKey 不应明文存储。

        服务器列表含其他实例的 API Key，需加密持久化（与 SMTP 密码一致）。
        """
        from app.db.models import ServerListModel

        plain_key = f"secret-{uuid.uuid4().hex}"
        client.put(
            "/admin/servers",
            headers=admin_headers,
            json=[
                {
                    "name": "S",
                    "url": "http://s:8000",
                    "apiKey": plain_key,
                    "ignoreSsl": "false",
                }
            ],
        )

        record = db_session.query(ServerListModel).first()
        assert record is not None, "服务器列表应持久化到数据库"
        stored = record.servers_json
        assert plain_key not in stored, "apiKey 不应明文存入数据库"

    def test_overwrite_servers_replaces_list(self, client, admin_headers):
        """重复保存应整体替换列表（全量语义），而非追加。"""
        client.put(
            "/admin/servers",
            headers=admin_headers,
            json=[
                {"name": "A", "url": "http://a:8000", "apiKey": "k1", "ignoreSsl": "false"}
            ],
        )
        client.put(
            "/admin/servers",
            headers=admin_headers,
            json=[
                {"name": "B", "url": "http://b:8000", "apiKey": "k2", "ignoreSsl": "false"}
            ],
        )

        response = client.get("/admin/servers", headers=admin_headers)
        data = response.json()
        assert [s["name"] for s in data] == ["B"]

    def test_invalid_payload_returns_400(self, client, admin_headers):
        """非法 payload（非 JSON 数组）应返回 400。"""
        response = client.put(
            "/admin/servers", headers=admin_headers, json={"name": "not-a-list"}
        )
        assert response.status_code == 400
