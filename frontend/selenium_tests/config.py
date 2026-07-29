import os

BASE_URL = os.environ.get("TEST_BASE_URL", "http://localhost:9000")
MOCK_BACKEND_URL = os.environ.get("MOCK_BACKEND_URL", "http://localhost:9000")
IMPLICIT_WAIT = 10
PAGE_LOAD_TIMEOUT = 30
BROWSER = os.environ.get("TEST_BROWSER", "chrome")
HEADLESS = os.environ.get("TEST_HEADLESS", "true").lower() == "true"

TEST_USERNAME = os.environ.get("TEST_USERNAME", "admin")
TEST_PASSWORD = os.environ.get("TEST_PASSWORD", "password")
DEBUG = os.environ.get("TEST_DEBUG", "false").lower() == "true"

# Docker / CI 环境下使用系统安装的 Chromium 和 ChromeDriver
CHROMIUM_BINARY = os.environ.get("CHROMIUM_BINARY", "")
CHROMEDRIVER_PATH = os.environ.get("CHROMEDRIVER_PATH", "")


def debug_sleep(seconds: float = 1.5):
    """调试模式下暂停指定秒数，便于观察操作过程。非调试模式立即返回。"""
    if DEBUG:
        import time
        time.sleep(seconds)
