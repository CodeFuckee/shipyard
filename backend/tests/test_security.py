import uuid
from app.db.models import APIKeyModel


class TestAPIAuthentication:
    def test_missing_api_key_returns_401(self, client):
        """缺少 X-API-Key 请求头时应返回 401。"""
        response = client.get("/containers")
        assert response.status_code == 401

    def test_invalid_api_key_returns_401(self, client):
        """无效的 API Key 应返回 401。"""
        response = client.get("/containers", headers={"X-API-Key": "invalid-key"})
        assert response.status_code == 401

    def test_valid_api_key_passes_auth(self, client, db_session):
        """有效的 API Key 应通过认证。"""
        key_str = uuid.uuid4().hex
        db_session.add(APIKeyModel(key=key_str, note="测试"))
        db_session.commit()

        # 由于没有 Docker daemon，请求可能返回 500（连接失败），但不会是 401 或 403
        response = client.get("/containers", headers={"X-API-Key": key_str})
        assert response.status_code not in (401, 403)


class TestAdminAuthentication:
    def test_missing_admin_headers_returns_401(self, client):
        """缺少管理员认证头时应返回 401。"""
        response = client.get("/admin/keys")
        assert response.status_code == 401

    def test_wrong_admin_password_returns_401(self, client):
        """错误的管理员密码应返回 401。"""
        response = client.get(
            "/admin/keys",
            headers={"X-Admin-User": "admin", "X-Admin-Pass": "wrong"},
        )
        assert response.status_code == 401

    def test_valid_admin_credentials(self, client, admin_headers):
        """正确的管理员凭据应通过认证。"""
        response = client.get("/admin/keys", headers=admin_headers)
        assert response.status_code == 200

    def test_change_password_requires_current_password(self, client, admin_headers):
        """当前密码错误时不应修改密码。"""
        response = client.post(
            "/admin/password",
            json={"current_password": "wrong", "new_password": "new-password"},
        )
        assert response.status_code == 401

        response = client.get("/admin/keys", headers=admin_headers)
        assert response.status_code == 200

    def test_change_password_updates_admin_authentication(self, client, admin_headers):
        """修改成功后仅新密码可用于管理员认证。"""
        response = client.post(
            "/admin/password",
            json={"current_password": "password", "new_password": "new-password"},
        )
        assert response.status_code == 200
        assert response.json() == {"message": "密码修改成功"}

        assert client.get("/admin/keys", headers=admin_headers).status_code == 401
        assert (
            client.get(
                "/admin/keys",
                headers={"X-Admin-User": "admin", "X-Admin-Pass": "new-password"},
            ).status_code
            == 200
        )


class TestAdminAPIKeys:
    def test_list_keys_empty(self, client, admin_headers):
        """初始时密钥列表应为空。"""
        response = client.get("/admin/keys", headers=admin_headers)
        assert response.status_code == 200
        assert response.json() == []

    def test_add_key_auto_generate(self, client, admin_headers):
        """添加密钥时若未指定 key 则自动生成。"""
        response = client.post("/admin/keys", headers=admin_headers, json={})
        assert response.status_code == 200
        data = response.json()
        assert "key" in data
        assert data["propagation"] == []

    def test_add_key_with_custom_value(self, client, admin_headers):
        """可以使用自定义 key 值添加。"""
        response = client.post(
            "/admin/keys",
            headers=admin_headers,
            json={"key": "my-custom-key", "note": "自定义"},
        )
        assert response.status_code == 200
        data = response.json()
        assert data["key"]["key"] == "my-custom-key"
        assert data["key"]["note"] == "自定义"

    def test_add_duplicate_key_fails(self, client, admin_headers):
        """重复的 key 应返回 400。"""
        client.post("/admin/keys", headers=admin_headers, json={"key": "dup-key"})
        response = client.post(
            "/admin/keys", headers=admin_headers, json={"key": "dup-key"}
        )
        assert response.status_code == 400

    def test_delete_key(self, client, admin_headers):
        """删除已存在的密钥。"""
        client.post("/admin/keys", headers=admin_headers, json={"key": "to-delete"})
        response = client.delete("/admin/keys/to-delete", headers=admin_headers)
        assert response.status_code == 200
        assert response.json() == {"status": "deleted"}

    def test_delete_nonexistent_key(self, client, admin_headers):
        """删除不存在的密钥应返回 404。"""
        response = client.delete("/admin/keys/no-such-key", headers=admin_headers)
        assert response.status_code == 404


class TestAdminNodes:
    def test_list_nodes_empty(self, client, admin_headers):
        """初始时节点列表应为空。"""
        response = client.get("/admin/nodes", headers=admin_headers)
        assert response.status_code == 200
        assert response.json() == []

    def test_add_node(self, client, admin_headers):
        """添加集群节点。"""
        response = client.post(
            "/admin/nodes",
            headers=admin_headers,
            json={
                "name": "node-1",
                "base_url": "http://10.0.0.1:8000",
                "admin_user": "admin",
                "admin_pass": "secret",
            },
        )
        assert response.status_code == 200
        data = response.json()
        assert data["name"] == "node-1"
        assert data["base_url"] == "http://10.0.0.1:8000"

    def test_add_node_missing_fields(self, client, admin_headers):
        """缺少必填字段应返回 400。"""
        response = client.post(
            "/admin/nodes",
            headers=admin_headers,
            json={"name": "incomplete"},
        )
        assert response.status_code == 400

    def test_add_duplicate_node_name_fails(self, client, admin_headers):
        """重复节点名应返回 400。"""
        client.post(
            "/admin/nodes",
            headers=admin_headers,
            json={
                "name": "dup-node",
                "base_url": "http://a.com",
                "admin_user": "u",
                "admin_pass": "p",
            },
        )
        response = client.post(
            "/admin/nodes",
            headers=admin_headers,
            json={
                "name": "dup-node",
                "base_url": "http://b.com",
                "admin_user": "u",
                "admin_pass": "p",
            },
        )
        assert response.status_code == 400

    def test_delete_node(self, client, admin_headers, db_session):
        """删除已存在的节点。"""
        resp = client.post(
            "/admin/nodes",
            headers=admin_headers,
            json={
                "name": "to-delete",
                "base_url": "http://x.com",
                "admin_user": "u",
                "admin_pass": "p",
            },
        )
        node_id = resp.json()["id"]

        response = client.delete(f"/admin/nodes/{node_id}", headers=admin_headers)
        assert response.status_code == 200
        assert response.json() == {"status": "deleted"}

    def test_delete_nonexistent_node(self, client, admin_headers):
        """删除不存在的节点应返回 404。"""
        response = client.delete("/admin/nodes/fake-id", headers=admin_headers)
        assert response.status_code == 404
