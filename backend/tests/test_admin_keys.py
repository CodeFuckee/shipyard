"""复现测试：Flutter 端删除 API Key 报 404。

用户报告：在 API Key 密钥管理页面删除 apikey 时，后端返回 404。

根因：Flutter 端 `_deleteKey` 优先取列表记录中的 `id` 字段（uuid 主键）
作为路径参数调用 `DELETE /admin/keys/{id}`（api_keys_screen.dart、
settings_screen.dart），而后端 `delete_key` 只按 `APIKeyModel.key`
（密钥字符串）字段查询，id ≠ key → 404 "Key not found"。
Web 管理端（web_ui.py）传的是 key 字段，所以 Web 端正常。

本测试模拟 Flutter 端行为：创建 key → 拉取列表 → 用列表中的 id 删除。
"""

import uuid


def _create_key(client, admin_headers):
    """用 admin 凭据创建一个 API key，返回 key 值。"""
    key_str = f"test-key-{uuid.uuid4().hex}"
    response = client.post(
        "/admin/keys",
        headers=admin_headers,
        json={"key": key_str, "note": "复现测试"},
    )
    assert response.status_code == 200, response.text
    return key_str


class TestAdminKeys:
    def test_delete_by_id_matches_flutter_frontend(self, client, admin_headers):
        """Flutter 端用列表记录的 id 删除 key 应成功（当前 404 复现）。"""
        key_str = _create_key(client, admin_headers)

        # GET /admin/keys 返回 ORM 序列化结果，含 id / key / note / created_at
        listed = client.get("/admin/keys", headers=admin_headers)
        assert listed.status_code == 200
        records = listed.json()
        assert any(r["key"] == key_str for r in records)

        # Flutter 端 _deleteKey: keyId = key['id']?.toString() ?? key['key']?.toString()
        record = next(r for r in records if r["key"] == key_str)
        record_id = record.get("id")

        # 按 id 删除（Flutter 端实际行为）
        response = client.delete(f"/admin/keys/{record_id}", headers=admin_headers)
        assert response.status_code == 200, (
            f"按 id 删除应成功，实际 {response.status_code}: {response.text}"
        )

        # 删除后列表中不应再存在该 key
        after = client.get("/admin/keys", headers=admin_headers)
        assert all(r["key"] != key_str for r in after.json())

    def test_delete_by_key_string_still_works(self, client, admin_headers):
        """按 key 字符串删除（Web 端行为）仍应正常。"""
        key_str = _create_key(client, admin_headers)

        response = client.delete(f"/admin/keys/{key_str}", headers=admin_headers)
        assert response.status_code == 200, response.text
