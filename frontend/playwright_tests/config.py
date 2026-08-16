"""Playwright E2E 测试配置（issue #39）。

所有配置均可通过环境变量覆盖，便于本地与 CI 灵活切换：
- TEST_BASE_URL：被测应用地址（默认 http://localhost:9000，由 mock backend 提供）
- TEST_USERNAME / TEST_PASSWORD：登录账号（默认 admin/password，与 mock backend 一致）
- CHROMIUM_EXECUTABLE：指定浏览器二进制（CI 可复用 frontend/.chrome 的 Chrome for Testing）
- TEST_CHANNEL：Playwright channel（如 chrome，使用系统 Chrome）
- TEST_HEADLESS：无头模式（CI 默认 true）
- TEST_ACTION_TIMEOUT：单步操作超时（毫秒）
- TEST_PAGE_LOAD_TIMEOUT：页面加载超时（毫秒）
"""
import os
import time

BASE_URL = os.environ.get("TEST_BASE_URL", "http://localhost:9000")
MOCK_BACKEND_URL = os.environ.get("MOCK_BACKEND_URL", "http://localhost:9000")
ACTION_TIMEOUT = int(os.environ.get("TEST_ACTION_TIMEOUT", "15000"))
PAGE_LOAD_TIMEOUT = int(os.environ.get("TEST_PAGE_LOAD_TIMEOUT", "60000"))
CHROMIUM_EXECUTABLE = os.environ.get("CHROMIUM_EXECUTABLE", "")
TEST_CHANNEL = os.environ.get("TEST_CHANNEL", "")
HEADLESS = os.environ.get("TEST_HEADLESS", "true").lower() == "true"
DEBUG = os.environ.get("TEST_DEBUG", "false").lower() == "true"
TEST_USERNAME = os.environ.get("TEST_USERNAME", "admin")
TEST_PASSWORD = os.environ.get("TEST_PASSWORD", "password")


def debug_sleep(seconds: float = 1.5):
    """调试模式下暂停指定秒数，便于观察操作过程；非调试模式立即返回。"""
    if DEBUG:
        time.sleep(seconds)
