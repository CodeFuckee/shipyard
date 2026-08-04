"""复现测试：主应用已登录，跳转到 /connect 授权页仍需重复输入用户名密码。

背景：用户在 10.0.0.122 的 shipyard 主应用（Web UI）登录过（凭据存于
localStorage，认证无状态），但从 10.0.0.169 添加 10.0.0.122 服务器并跳转
授权页后，授权页仍要求重新输入用户名密码。

根因：主应用登录（POST /admin/login）与 /connect 授权流程登录
（POST /connect/login）是两个完全隔离的会话体系——主应用登录不种
connect_session cookie，授权页 /connect/session 仅凭该 cookie 判定登录态，
因此已登录用户被误判为未登录。

修复方向：主应用登录成功后同步创建 connect 会话并种 cookie，使授权页
复用主应用登录态，直接显示"确认并添加"。
"""

REDIRECT_URI = "http://10.0.0.169:8080/connect/callback"
CODE_CHALLENGE = "a" * 43  # PKCE code_challenge 最少 43 字符


class TestConnectAuthFlow:
    def test_admin_login_establishes_connect_session(self, client, admin_headers):
        """主应用登录成功后，/connect/session 应识别为已登录。

        用户已在目标服务器主应用登录（无需再输入密码），跳转授权页时
        /connect/session 必须返回 logged_in=true，直接显示确认按钮。
        """
        login_resp = client.post("/admin/login", headers=admin_headers)
        assert login_resp.status_code == 200

        session_resp = client.get("/connect/session")
        assert session_resp.status_code == 200
        assert session_resp.json()["logged_in"] is True, (
            "主应用登录后授权页仍判定未登录，需重复输入用户名密码"
        )

    def test_connect_confirm_after_admin_login(self, client, admin_headers):
        """主应用登录后，授权确认流程无需再次输入密码即可完成。

        完整链路：主应用登录 → 注册 client → 授权页直接确认（POST
        /connect/confirm）→ 302 回跳携带一次性 code。
        """
        login_resp = client.post("/admin/login", headers=admin_headers)
        assert login_resp.status_code == 200

        reg_resp = client.post(
            "/connect/register", json={"redirect_uri": REDIRECT_URI, "client_name": "测试客户端"}
        )
        assert reg_resp.status_code == 200
        client_id = reg_resp.json()["client_id"]

        confirm_resp = client.post(
            "/connect/confirm",
            data={
                "client_id": client_id,
                "redirect_uri": REDIRECT_URI,
                "state": "state-123",
                "code_challenge": CODE_CHALLENGE,
            },
            # 回跳地址是外部服务器（源 app），不跟随重定向
            follow_redirects=False,
        )
        assert confirm_resp.status_code == 302, (
            "主应用登录后确认授权不应返回 401（未登录），实际 "
            f"status={confirm_resp.status_code}"
        )
        location = confirm_resp.headers["location"]
        assert "code=" in location and "state=state-123" in location

    def test_connect_confirm_requires_login_without_session(self, client):
        """未登录（无任何会话）时确认授权应返回 401——确认按钮仍需要登录保护。"""
        reg_resp = client.post(
            "/connect/register", json={"redirect_uri": REDIRECT_URI}
        )
        client_id = reg_resp.json()["client_id"]

        confirm_resp = client.post(
            "/connect/confirm",
            data={
                "client_id": client_id,
                "redirect_uri": REDIRECT_URI,
                "state": "s",
                "code_challenge": CODE_CHALLENGE,
            },
        )
        assert confirm_resp.status_code == 401

    def test_admin_login_failure_sets_no_session(self, client):
        """登录失败不应种会话 cookie，授权页仍应判定未登录。"""
        bad = client.post(
            "/admin/login",
            headers={"X-Admin-User": "admin", "X-Admin-Pass": "wrong-password"},
        )
        assert bad.status_code == 401

        session_resp = client.get("/connect/session")
        assert session_resp.json()["logged_in"] is False


class TestConnectSessionBind:
    """授权页自动绑定浏览器中已有的主应用 API key（旧登录态免重复输入密码）。

    场景：用户在目标服务器主应用登录过（API key 存浏览器 localStorage，
    可能是 /admin/login 种 cookie 功能上线前的旧登录态，无 connect_session
    cookie），跳转授权页时应自动识别该 key 并建立会话，直接显示确认按钮。
    """

    def test_bind_with_valid_api_key(self, client, admin_headers):
        """浏览器存有主应用 API key（无 connect cookie）时，POST /connect/session
        应校验 key、建立会话并种 cookie，之后授权页免登录。"""
        # 模拟旧登录态：先登录拿 key，但丢弃返回的 connect_session cookie
        login_resp = client.post("/admin/login", headers=admin_headers)
        assert login_resp.status_code == 200
        api_key = login_resp.json()["api_key"]
        client.cookies.clear()  # 丢弃 cookie，仅保留 key（等价于旧登录态浏览器）

        bind_resp = client.post("/connect/session", json={"api_key": api_key})
        assert bind_resp.status_code == 200
        assert bind_resp.json()["logged_in"] is True, (
            "主应用已有 API key 的浏览器跳转授权页仍判定未登录，需重复输入密码"
        )
        assert "connect_session" in bind_resp.headers.get("set-cookie", "")

        # 绑定后授权页会话检查应免登录
        session_resp = client.get("/connect/session")
        assert session_resp.json()["logged_in"] is True

    def test_bind_then_confirm_without_login(self, client, admin_headers):
        """绑定主应用 key 后，确认授权直接 302 回跳，无需 /connect/login。"""
        login_resp = client.post("/admin/login", headers=admin_headers)
        api_key = login_resp.json()["api_key"]
        client.cookies.clear()

        bind_resp = client.post("/connect/session", json={"api_key": api_key})
        assert bind_resp.json()["logged_in"] is True

        reg_resp = client.post(
            "/connect/register", json={"redirect_uri": REDIRECT_URI}
        )
        client_id = reg_resp.json()["client_id"]

        confirm_resp = client.post(
            "/connect/confirm",
            data={
                "client_id": client_id,
                "redirect_uri": REDIRECT_URI,
                "state": "s",
                "code_challenge": CODE_CHALLENGE,
            },
            follow_redirects=False,
        )
        assert confirm_resp.status_code == 302, (
            "绑定主应用 key 后确认授权不应返回 401，实际 "
            f"status={confirm_resp.status_code}"
        )
        assert "code=" in confirm_resp.headers["location"]

    def test_bind_rejects_invalid_key(self, client):
        """无效 API key 不能建立会话（不种 cookie），授权页仍显示登录表单。"""
        resp = client.post("/connect/session", json={"api_key": "not-a-real-key"})
        assert resp.status_code == 200
        assert resp.json()["logged_in"] is False
        assert "connect_session" not in resp.headers.get("set-cookie", "")

        session_resp = client.get("/connect/session")
        assert session_resp.json()["logged_in"] is False

    def test_bind_requires_api_key_field(self, client):
        """缺少 api_key 字段应返回 422（参数校验错误）。"""
        resp = client.post("/connect/session", json={})
        assert resp.status_code == 422
