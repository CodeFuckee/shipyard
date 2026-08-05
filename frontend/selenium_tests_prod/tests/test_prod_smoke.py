"""生产环境只读冒烟测试。

与 frontend/selenium_tests（本地 mock 环境）区分：
- 直接测试部署在生产环境的真实页面
- 只做只读验证（页面可访问、能渲染、能登录、导航正常），
  不执行任何写操作，对生产环境零影响
- 每个测试对 TEST_PROD_URLS 中的每个环境各跑一遍（见 conftest.py 参数化）

注意：生产环境 Flutter 应用启动较慢（CanvasKit 加载 + 语义树构建
可能 30s+），页面相关断言前需轮询等待渲染完成。
"""

import time

import pytest

from config import NAV_TABS
from conftest import get_flutter_diagnostics

pytestmark = pytest.mark.prod_smoke


def _page_has_content(driver) -> bool:
    """页面 body 是否渲染出文本内容（Flutter CanvasKit 语义树）。"""
    text = driver.execute_script("return document.body.innerText") or ""
    return len(text.strip()) > 0


def _wait_flutter_rendered(driver, timeout: int = 90) -> dict:
    """轮询等待 flutter-view 渲染完成，返回最新诊断信息。"""
    deadline = time.time() + timeout
    diag = get_flutter_diagnostics(driver)
    while time.time() < deadline:
        if diag.get("flutter_view_exists") and diag.get("semantics_children", 0) > 0:
            return diag
        print(f"[rendered] {diag}")  # 临时调试
        time.sleep(3)
        diag = get_flutter_diagnostics(driver)
    return diag


class TestProdReachability:
    """生产环境连通性检查（不依赖浏览器）。"""

    def test_at_least_one_prod_env_reachable(self, reachability, prod_urls):
        """至少一个生产环境可达，否则本次测试全部失去意义，直接失败。"""
        reachable = [url for url, (ok, _) in reachability.items() if ok]
        assert reachable, (
            "所有生产环境均不可达，请检查网络/服务状态:\n"
            + "\n".join(
                f"  - {url}: {reason}" for url, (_, reason) in reachability.items()
            )
            + f"\n配置的环境: {prod_urls}"
        )


class TestProdPageLoad:
    """页面可访问性与基础渲染（不依赖登录）。"""

    def test_flutter_app_renders(self, driver):
        """Flutter 应用正常渲染：flutter-view 出现、语义树有内容。"""
        diag = _wait_flutter_rendered(driver)
        # 诊断接口自身异常（execute_script 失败）视为失败，但给出明确错误
        assert not diag.get("execute_script_error"), f"诊断失败: {diag}"
        assert diag["flutter_view_exists"], f"flutter-view 未渲染: {diag}"
        assert diag["canvas_count"] > 0 or diag.get("semantics_children", 0) > 0, (
            f"画布与语义树均为空，页面未实际渲染: {diag}"
        )
        # JS 错误仅打印警告：语义树模式下 Flutter 引擎有 DOM 竞争噪音
        # （如 removeAttribute null），页面仍正常工作
        js_errors = diag.get("js_errors", [])
        if js_errors:
            print(f"[warn] 页面 JS 错误（引擎噪音，页面继续工作）: {js_errors}")

    def test_semantics_enabled(self, driver):
        """语义树已启用（登录与导航测试的前提）。"""
        diag = _wait_flutter_rendered(driver)
        assert diag.get("semantics_children", 0) > 0, f"语义树为空: {diag}"


class TestProdLogin:
    """登录与主界面（需要 TEST_USERNAME/TEST_PASSWORD，缺失自动跳过）。"""

    @pytest.fixture(autouse=True)
    def _logged_in(self, do_login):
        pass

    def test_login_navbar_visible(self, driver):
        """登录成功后底部导航栏可见。"""
        from pages.nav_bar import NavBar

        nav = NavBar(driver)
        assert nav.is_visible(), "登录后导航栏不可见"
        assert nav.tab_exists("Dashboard") and nav.tab_exists("Containers")

    def test_nav_tabs_render_content(self, driver):
        """依次切换各导航 tab，每个页面均渲染出内容（只读检查）。"""
        from pages.nav_bar import NavBar

        nav = NavBar(driver)
        for tab in NAV_TABS:
            nav.click_tab(tab)
            # 等待页面内容渲染（生产环境网络较慢，放宽等待）
            for _ in range(15):
                if _page_has_content(driver):
                    break
                time.sleep(1)
            assert _page_has_content(driver), f"tab [{tab}] 页面无内容"
            diag = get_flutter_diagnostics(driver)
            js_errors = diag.get("js_errors", [])
            if js_errors:
                # 语义树引擎噪音（DOM 竞争），页面继续工作则仅警告
                print(
                    f"[warn] tab [{tab}] 切换后 JS 错误"
                    f"（引擎噪音，页面继续工作）: {js_errors}"
                )
