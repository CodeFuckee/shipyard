"""生产环境认证错误场景测试。

背景：概览页（Dashboard）对所有 API 请求失败时会把后端返回的原始
错误直接显示在页面上（toast + 服务器卡片错误），且每 3 秒重试。
当浏览器 localStorage 中存有无效的 API Key（过期/被删除/其他实例的
key，如访问 https://home.chenkaidi.top:508/v2/ 时浏览器残留旧实例
token），AuthGate 只检查 token 是否存在而不验证有效性，用户会直接
进入概览页并看到 "Invalid API Key or Admin Credentials" 报错。

本文件验证两个场景：
1. 预置无效 token：不应进入概览页直接显示认证错误，应回到登录页
   （无需登录凭据，任何环境可跑）
2. 登录成功后进入概览页：不应出现认证错误文本
   （需要 TEST_USERNAME/TEST_PASSWORD，缺失自动跳过）

与 test_prod_smoke.py 的登录流程共用 conftest 的 do_login fixture。
"""

import json
import time

import pytest

from conftest import get_flutter_diagnostics

pytestmark = pytest.mark.prod_smoke

# 认证错误关键字（后端 401 时前端直接展示的原始文案/常见等价形式）
AUTH_ERROR_KEYWORDS = [
    "invalid api key",
    "admin credentials",
    "unauthorized",
]


def _page_text(driver) -> str:
    """获取页面语义树文本（Flutter CanvasKit 渲染的 body.innerText）。"""
    try:
        return driver.execute_script("return document.body.innerText") or ""
    except Exception:
        return ""


def _has_auth_error(text: str) -> bool:
    lower = (text or "").lower()
    return any(kw in lower for kw in AUTH_ERROR_KEYWORDS)


def _wait_rendered(driver, timeout: int = 120) -> str:
    """轮询等待页面渲染出文本内容，返回最终页面文本。"""
    deadline = time.time() + timeout
    text = ""
    while time.time() < deadline:
        text = _page_text(driver)
        if text.strip():
            return text
        time.sleep(3)
    return text


def _inject_invalid_token(driver, prod_url: str):
    """向浏览器注入无效 API Key（shared_preferences web 的 JSON 编码格式）。

    key 必须带 `flutter.` 前缀（shared_preferences 默认前缀），字符串值
    以 JSON 编码（带引号）存储，否则 Flutter 解码失败等同于无 token，
    无法复现"无效 token 进入概览页"的场景。
    """
    script = f"""
        var p = {json.dumps(prod_url)};
        var t = '"invalid_token_probe_xxx"';
        localStorage.setItem('flutter.docker_auth_token', t);
        localStorage.setItem('flutter.docker_auth_server_url', JSON.stringify(p));
        localStorage.setItem('flutter.docker_api_key', t);
        localStorage.setItem('flutter.docker_api_url', JSON.stringify(p));
        localStorage.setItem('flutter.web_backend_token', t);
        localStorage.setItem('flutter.web_backend_url', JSON.stringify(p));
        localStorage.removeItem('flutter.server_list');
    """
    driver.execute_script(script)


class TestProdInvalidToken:
    """预置无效 token：应回到登录页而不是概览页直接显示认证错误。"""

    @pytest.fixture(autouse=True)
    def _inject_and_reload(self, driver, prod_url):
        """driver 已加载页面：注入无效 token 后重新导航，模拟残留旧凭据。"""
        _inject_invalid_token(driver, prod_url)
        driver.get(driver.current_url)  # 重新加载（保留 localStorage）
        yield

    def test_no_auth_error_on_dashboard(self, driver, prod_url):
        """进入页面不应出现 "Invalid API Key or Admin Credentials" 类错误。"""
        text = _wait_rendered(driver)
        assert text.strip(), "页面未渲染出任何内容"
        assert not _has_auth_error(text), (
            "页面直接显示了认证错误（无效 token 未被拦截，进入了概览页）：\n"
            f"{text[:600]}"
        )

    def test_back_to_login_page(self, driver, prod_url):
        """无效 token 时应回到登录页，而不是停留在报错的概览页。"""
        text = _wait_rendered(driver)
        lower = text.lower()
        # 登录页特征：登录按钮文案（"登录"/"Login"）是登录页独有，
        # 概览页导航栏为 Dashboard/Containers 等，无"登录"字样。
        # 语义树构建初期输入框 label 尚未填充，只需登录按钮特征即可。
        is_login = "登录" in text or "login" in lower
        assert is_login, (
            "无效 token 后未回到登录页，页面文本：\n"
            f"{text[:600]}"
        )
        assert not _has_auth_error(text), (
            "回到登录页但页面残留认证错误文本：\n"
            f"{text[:600]}"
        )


class TestProdDashboardNoAuthError:
    """登录成功后进入概览页不应有认证错误（需要生产凭据，缺失自动跳过）。"""

    @pytest.fixture(autouse=True)
    def _logged_in(self, do_login):
        pass

    def test_dashboard_no_auth_error(self, driver, prod_url):
        """进入概览页面没有直接的认证报错。"""
        from pages.nav_bar import NavBar

        nav = NavBar(driver)
        assert nav.is_visible(), "登录后导航栏不可见，登录可能失败"
        # 切到概览 tab（Dashboard 默认页）并等待内容渲染
        nav.click_tab("Dashboard")
        deadline = time.time() + 90
        text = ""
        while time.time() < deadline:
            text = _page_text(driver)
            if len(text.strip()) > 20:  # 页面有实质内容
                break
            time.sleep(3)
        assert not _has_auth_error(text), (
            "概览页直接显示了认证错误：\n"
            f"{text[:600]}"
        )
        # 诊断信息记录（便于排查）
        diag = get_flutter_diagnostics(driver)
        js_errors = diag.get("js_errors", [])
        if js_errors:
            print(f"[warn] 概览页 JS 错误（引擎噪音，页面继续工作则忽略）: {js_errors}")
