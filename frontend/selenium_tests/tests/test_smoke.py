"""冒烟测试 — 不依赖目标服务器的框架验证"""

import os
import sys

import pytest
from selenium import webdriver
from selenium.webdriver.chrome.service import Service as ChromeService
from webdriver_manager.chrome import ChromeDriverManager

# 确保 selenium_tests 目录在 sys.path 中，以便导入 conftest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from conftest import _get_chrome_version, _find_cached_chromedriver, _get_chromedriver_version  # noqa: E402


_SYSTEM_CHROMEDRIVER = os.environ.get("CHROMEDRIVER_PATH", "")
_CHROMIUM_BINARY = os.environ.get("CHROMIUM_BINARY", "")


@pytest.fixture(scope="session")
def chromedriver_path():
    """会话级别：获取 ChromeDriver 路径。
    优先从缓存加载匹配版本（避免网络请求），Docker 环境使用系统安装的 chromedriver。
    """
    if _SYSTEM_CHROMEDRIVER:
        return _SYSTEM_CHROMEDRIVER

    chrome_info = _get_chrome_version()
    if chrome_info:
        cached = _find_cached_chromedriver(chrome_info[1])
        if cached:
            print(f"[chromedriver] 使用缓存: {cached}")
            return cached

    # 查找系统 PATH 中的 chromedriver（如 Homebrew 安装的）
    import shutil
    system_cd = shutil.which("chromedriver")
    if system_cd:
        # 检查系统 chromedriver 版本是否与 Chrome 匹配
        cd_info = _get_chromedriver_version(system_cd)
        if cd_info and chrome_info and cd_info[1] != chrome_info[1]:
            print(
                f"[chromedriver] 系统 chromedriver 版本 ({cd_info[1]}) "
                f"与 Chrome ({chrome_info[1]}) 不匹配，跳过"
            )
        else:
            print(f"[chromedriver] 使用系统安装: {system_cd}")
            return system_cd

    print("[chromedriver] 缓存未命中，由 webdriver-manager 下载...")
    return ChromeDriverManager().install()


@pytest.fixture(scope="function")
def chrome_driver(chromedriver_path):
    """每个测试函数独立的 Chrome/Chromium 实例"""
    options = webdriver.ChromeOptions()
    if _CHROMIUM_BINARY:
        options.binary_location = _CHROMIUM_BINARY
    options.add_argument("--headless=new")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--ignore-certificate-errors")
    options.add_argument("--test-type")
    options.add_argument("--use-gl=egl")
    options.add_argument("--enable-unsafe-swiftshader")
    options.add_argument("--ignore-gpu-blocklist")
    d = webdriver.Chrome(service=ChromeService(chromedriver_path), options=options)
    yield d
    d.quit()


@pytest.mark.smoke
class TestSeleniumFramework:
    """验证 Selenium 和 WebDriver 是否正常工作"""

    def test_webdriver_manager_can_download(self, chromedriver_path):
        """WebDriver Manager 或系统安装提供了 ChromeDriver"""
        if _SYSTEM_CHROMEDRIVER:
            pytest.skip("Docker 环境使用系统 chromedriver，跳过 webdriver-manager 下载测试")
        assert chromedriver_path, "ChromeDriver 下载路径不应为空"

    def test_can_create_driver(self, chrome_driver):
        """能创建 Chrome/Chromium 实例"""
        assert chrome_driver is not None

    def test_driver_can_navigate(self, chrome_driver):
        """浏览器能导航到页面"""
        chrome_driver.get("data:text/html,<h1>Hello</h1>")
        assert "Hello" in chrome_driver.page_source
