import os

# 生产环境测试目标地址（逗号分隔支持多个环境，每个环境独立跑一遍测试）。
# 默认指向实际部署的两套生产环境，可通过 TEST_PROD_URLS 覆盖。
PROD_URLS = [
    u.strip()
    for u in os.environ.get(
        "TEST_PROD_URLS",
        "https://home.chenkaidi.top:507,http://10.0.0.122:8080",
    ).split(",")
    if u.strip()
]

# 网页授权添加服务器测试（test_prod_connect.py）的源/目标服务器。
# 源服务器：在其 Web 界面上发起授权添加；目标服务器：被添加的服务器。
CONNECT_SOURCE_URL = os.environ.get(
    "TEST_CONNECT_SOURCE_URL", "https://home.chenkaidi.top:507"
)
CONNECT_TARGET_URL = os.environ.get(
    "TEST_CONNECT_TARGET_URL", "http://10.0.0.122:8080"
)
# 显式指定授权测试使用的目标地址（本地 https 代理等），默认自动处理
CONNECT_PROXY_URL = os.environ.get("TEST_CONNECT_PROXY_URL", "")

IMPLICIT_WAIT = 10
PAGE_LOAD_TIMEOUT = 60
BROWSER = os.environ.get("TEST_BROWSER", "chrome")
HEADLESS = os.environ.get("TEST_HEADLESS", "true").lower() == "true"

# 生产环境登录凭据：必须通过环境变量注入，禁止硬编码。
# 未设置时，需要登录的测试会被跳过（见 conftest.py 的 do_login）。
TEST_USERNAME = os.environ.get("TEST_USERNAME", "")
TEST_PASSWORD = os.environ.get("TEST_PASSWORD", "")

# 目标服务器授权页登录凭据（网页授权添加测试用）。
# 默认与源服务器凭据相同，可通过 TEST_CONNECT_USERNAME / TEST_CONNECT_PASSWORD
# 单独覆盖（两套服务器管理员账号可能不同）。
TEST_CONNECT_USERNAME = os.environ.get(
    "TEST_CONNECT_USERNAME", TEST_USERNAME
)
TEST_CONNECT_PASSWORD = os.environ.get(
    "TEST_CONNECT_PASSWORD", TEST_PASSWORD
)
DEBUG = os.environ.get("TEST_DEBUG", "false").lower() == "true"

# Docker / CI 环境下使用系统安装的 Chromium 和 ChromeDriver
CHROMIUM_BINARY = os.environ.get("CHROMIUM_BINARY", "")
CHROMEDRIVER_PATH = os.environ.get("CHROMEDRIVER_PATH", "")

# 底部导航标签名（只读冒烟测试逐个切换验证渲染）
NAV_TABS = ["Dashboard", "Containers", "Resources", "Settings"]


def debug_sleep(seconds: float = 1.5):
    """调试模式下暂停指定秒数，便于观察操作过程。非调试模式立即返回。"""
    if DEBUG:
        import time
        time.sleep(seconds)
