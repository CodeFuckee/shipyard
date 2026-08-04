"""复现测试：网页授权（/connect）添加服务器后，签发的独立 apikey 认证失败。

用户报告：通过网页授权添加服务器后，服务器列表仍是 1 个，API 密钥管理多了一条
connect 记录，但用该 key 请求目标服务器 /images 一直拉取失败（401 或其它错误）。

本测试完整模拟授权流程：登录 → 注册 client → 确认授权 → token 交换 → 用签发
的独立 apikey 访问受保护端点，验证认证链路是否可用。
"""

import re

REDIRECT_URI = "http://10.0.0.169:8080/connect/callback"
CODE_VERIFIER = "b" * 48  # 与前端 _randomToken(48) 长度一致
# SHA-256(CODE_VERIFIER) 的 hex 值，与前端 _sha256Hex 算法一致
import hashlib

CODE_CHALLENGE = hashlib.sha256(CODE_VERIFIER.encode()).hexdigest()


def _register_client(client):
    reg = client.post(
        "/connect/register",
        json={"redirect_uri": REDIRECT_URI, "client_name": "测试客户端"},
    )
    assert reg.status_code == 200
    return reg.json()["client_id"]


def _confirm_and_get_code(client, client_id):
    confirm = client.post(
        "/connect/confirm",
        data={
            "client_id": client_id,
            "redirect_uri": REDIRECT_URI,
            "state": "state-xyz",
            "code_challenge": CODE_CHALLENGE,
        },
        follow_redirects=False,
    )
    assert confirm.status_code == 302
    return re.search(r"code=([0-9a-f]+)", confirm.headers["location"]).group(1)


def _exchange_token(client, client_id, code):
    token_resp = client.post(
        "/connect/token",
        json={
            "client_id": client_id,
            "code": code,
            "code_verifier": CODE_VERIFIER,
        },
    )
    assert token_resp.status_code == 200, token_resp.text
    return token_resp.json()["apikey"]


class TestConnectIssuedKey:
    def test_full_flow_then_authenticate_images(self, client, admin_headers):
        """完整授权流程后，用签发的 apikey 请求 /images 必须通过认证（非 401）。

        用户症状「获取另外一个服务器的信息时一直拉取失败」：源 app 用授权
        签发的独立 apikey 请求目标服务器 /images。若认证失败（401），
        前端任何页面都无法拉取数据。
        """
        # 1. 主应用登录（建立 connect 会话 + 获取登录 key）
        login = client.post("/admin/login", headers=admin_headers)
        assert login.status_code == 200

        # 2. 注册 public client
        client_id = _register_client(client)

        # 3. 授权页确认 → 302 回跳携带一次性 code
        code = _confirm_and_get_code(client, client_id)

        # 4. 用 code + verifier 交换独立 apikey
        apikey = _exchange_token(client, client_id, code)

        # 5. 关键：用签发的 apikey 请求 /images，认证必须通过
        # （测试环境无 Docker socket，500 属预期，401 即复现认证失败）
        images_resp = client.get("/images", headers={"X-API-Key": apikey})
        assert images_resp.status_code != 401, (
            "connect 流程签发的 apikey 认证失败，前端拉取镜像列表将一直失败："
            f"GET /images 返回 {images_resp.status_code}"
        )

    def test_issued_key_can_manage_server_list(self, client, admin_headers):
        """签发的 apikey 应能读写服务器列表（/admin/servers）。

        授权页宣称签发「管理员级 API 密钥」，源 app 授权后需把新服务器写入
        自己的服务器列表（PUT /admin/servers）。若该 key 认证失败，
        服务器列表永远只有旧条目——用户报告的「服务器列表还是只有一个服务器」。
        """
        login = client.post("/admin/login", headers=admin_headers)
        assert login.status_code == 200
        client_id = _register_client(client)
        code = _confirm_and_get_code(client, client_id)
        apikey = _exchange_token(client, client_id, code)

        resp = client.put(
            "/admin/servers",
            headers={"X-API-Key": apikey},
            json=[
                {"name": "旧服务器", "url": "http://10.0.0.169:8080", "apiKey": "old-key", "ignoreSsl": "false"},
                {"name": "新服务器", "url": REDIRECT_URI.replace("/connect/callback", ""), "apiKey": apikey, "ignoreSsl": "false"},
            ],
        )
        assert resp.status_code == 200, (
            "connect 签发的 apikey 无法保存服务器列表，"
            f"实际 status={resp.status_code}"
        )

        # 读回验证
        get_resp = client.get("/admin/servers", headers={"X-API-Key": apikey})
        assert get_resp.status_code == 200
        servers = get_resp.json()
        assert len(servers) == 2

    def test_issued_key_in_keys_list(self, client, admin_headers, db_session):
        """签发的 apikey 应出现在 API 密钥管理列表（/admin/keys）。

        用户已确认「API 密钥管理的地方多了一条记录」——key 确实落库，
        这是本 bug 的对照组：key 在列表可见，但认证/使用失败才叫 bug。
        """
        login = client.post("/admin/login", headers=admin_headers)
        client_id = _register_client(client)
        code = _confirm_and_get_code(client, client_id)
        apikey = _exchange_token(client, client_id, code)

        keys_resp = client.get("/admin/keys", headers=admin_headers)
        keys = keys_resp.json()
        assert any(k["key"] == apikey for k in keys), "签发的 apikey 应出现在密钥管理列表"
