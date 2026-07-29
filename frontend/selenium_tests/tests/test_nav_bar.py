import time

import pytest
from pages.nav_bar import NavBar
from conftest import TAB_NAMES


@pytest.fixture(autouse=True)
def login(do_login):
    yield


class TestNavBar:
    """底部导航栏综合测试。"""

    def test_nav_bar_exists_and_has_tabs(self, driver):
        nav = NavBar(driver)
        assert nav.is_visible(), "主界面应显示底部导航栏"

        found = [t for t in TAB_NAMES if nav.tab_exists(t)]
        assert len(found) >= 2, f"应至少找到 2 个导航标签，实际找到: {found}"

    def test_nav_bar_is_floating(self, driver):
        """验证导航栏悬浮在页面内容上方，不独占一行。

        检查要点：
        1. 导航栏标签存在
        2. flutter-view 占满整个视口，外部无独立的导航占位元素
        3. 页面滚动后导航栏依旧可见（悬浮不随内容滚走）
        """
        nav = NavBar(driver)
        assert nav.is_visible(), "导航栏应可见"

        # flutter-view 应占满视口高度，不应有独立占位区域
        view_bottom = driver.execute_script("""
            var fv = document.querySelector('flutter-view');
            if (!fv) return 0;
            return fv.getBoundingClientRect().bottom;
        """)
        win_height = driver.execute_script("return window.innerHeight")
        assert view_bottom >= win_height - 10, (
            f"flutter-view 底部({view_bottom:.0f})应接近窗口底部({win_height})，"
            f"悬浮模式下导航栏不占用独立空间"
        )

        # 页面滚动后导航栏标签仍然可见
        driver.execute_script("window.scrollBy(0, 400)")
        time.sleep(1)
        assert nav.is_visible(), "滚动后导航栏应仍然可见（悬浮固定）"

        driver.execute_script("window.scrollBy(0, -400)")
        time.sleep(1)
        assert nav.is_visible(), "滚回顶部后导航栏应仍然可见"
