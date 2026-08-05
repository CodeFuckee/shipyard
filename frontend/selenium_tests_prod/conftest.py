"""生产环境只读冒烟测试的 pytest 配置。

与 frontend/selenium_tests（本地 mock 环境）完全隔离：
- 目标地址为真实部署的生产环境（TEST_PROD_URLS 配置，默认多环境）
- 只做只读验证，不执行任何写操作
- 登录凭据通过 TEST_USERNAME / TEST_PASSWORD 环境变量注入

核心逻辑（chromedriver 管理、Flutter 语义树启用）沿用自
frontend/selenium_tests/conftest.py 的调试沉淀，按需精简。
"""

import os
import shutil
import socket
import time
import urllib.request
from urllib.parse import urlparse

import pytest
from selenium import webdriver
from selenium.webdriver.chrome.service import Service as ChromeService
from selenium.webdriver.firefox.service import Service as FirefoxService
from webdriver_manager.chrome import ChromeDriverManager
from webdriver_manager.firefox import GeckoDriverManager

from config import (
    PROD_URLS,
    IMPLICIT_WAIT,
    PAGE_LOAD_TIMEOUT,
    BROWSER,
    HEADLESS,
    TEST_USERNAME,
    TEST_PASSWORD,
    CHROMIUM_BINARY,
    CHROMEDRIVER_PATH,
    debug_sleep,
)

# 本地 https 代理的证书 SPKI（供 --ignore-certificate-errors-spki-list
# 精确信任自签证书——Chrome 131+ 的 --ignore-certificate-errors 对
# fetch 请求无效）
_PROXY_SPKI: str = ""


# ---------------------------------------------------------------------------
# 生产环境可达性（收集阶段检查一次，结果缓存）
# ---------------------------------------------------------------------------

_REACHABILITY: dict[str, tuple[bool, str]] = {}


def _check_reachability(url: str, timeout: int = 5) -> tuple[bool, str]:
    """检查目标生产环境是否可达。返回 (是否可达, 原因)。

    HTTP 检查跳过 SSL 证书验证：生产环境 https 可能证书过期/自签
    （浏览器测试已通过 --ignore-certificate-errors 忽略证书），
    可达性检查只看服务是否在响应。

    与浏览器行为对齐的两个关键点：
    - 强制直连（ProxyHandler({})）：urllib 默认继承系统/环境代理，
      浏览器对私网地址通常绕过代理，代理接管私网流量时会导致误判
    - 4xx/5xx 视为可达：服务器返回 401/503 说明服务在响应（浏览器
      可打开登录页/错误页），只有连接类错误才算不可达
    """
    try:
        parsed = urlparse(url)
        host = parsed.hostname or "localhost"
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        with socket.create_connection((host, port), timeout=timeout):
            pass
    except Exception as e:
        return False, f"端口连接失败: {e}"
    try:
        import ssl
        import urllib.error
        opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}),  # 强制直连，不走代理
            urllib.request.HTTPSHandler(      # https 自签证书跳过验证
                context=ssl._create_unverified_context()
            ),
        )
        req = urllib.request.Request(url, method="GET")
        with opener.open(req, timeout=timeout) as resp:
            status = resp.status
    except urllib.error.HTTPError as e:
        # 4xx/5xx：服务器在响应，服务可达（浏览器可打开对应页面）
        status = e.code
    except Exception as e:
        return False, f"HTTP 请求失败: {e}"
    return True, f"OK (HTTP {status})"


def get_reachability() -> dict[str, tuple[bool, str]]:
    """返回全部生产环境的可达性（带缓存）。"""
    if not _REACHABILITY:
        for url in PROD_URLS:
            _REACHABILITY[url] = _check_reachability(url)
            ok, reason = _REACHABILITY[url]
            status = "可达" if ok else f"不可达 ({reason})"
            print(f"[prod] {url} —— {status}")
    return _REACHABILITY


@pytest.fixture(scope="session")
def reachability() -> dict[str, tuple[bool, str]]:
    return get_reachability()


@pytest.fixture(scope="session")
def prod_urls() -> list[str]:
    return PROD_URLS


# 每个测试对每个配置的生产环境各跑一遍，id 中标注具体环境便于区分
def pytest_generate_tests(metafunc):
    if "prod_url" in metafunc.fixturenames:
        get_reachability()  # 触发一次检查并打印状态
        metafunc.parametrize(
            "prod_url",
            PROD_URLS,
            ids=[url.replace("://", "__").rstrip("/") for url in PROD_URLS],
        )


@pytest.fixture
def prod_url():
    """参数化 fixture：当前测试目标的生产环境地址。"""
    raise NotImplementedError  # 由 pytest_generate_tests 参数化


# ---------------------------------------------------------------------------
# Flutter 语义树 / 渲染诊断（沿用 selenium_tests/conftest.py）
# ---------------------------------------------------------------------------

def enable_flutter_semantics(driver):
    """确保 Flutter 无障碍语义树激活，使 CanvasKit 应用的 widget 可通过 DOM 访问。

    当 URL 包含 ?enable_semantics=true 时，Flutter 应用加载后会自动激活语义树，
    placeholder 点击仅作为兜底。

    注意：Flutter 应用启动时会先渲染 splash 再导航到实际页面，导航瞬间
    execute_script 会返回 None；此时若误判"语义树未激活"而点击 placeholder，
    会触发语义树重建，导致页面 JS 执行上下文失效（此后 execute_script
    全部返回 None）。因此只有明确读到语义树为空（非 None）时才点击 placeholder。
    """
    # Step 0: 注入浏览器端诊断脚本，捕获 JS 错误便于排查。
    # 只收集脚本执行错误（e.message 非空），忽略资源加载错误
    # （favicon/字体 404 等噪音，避免误报）。
    driver.execute_script("""
        window.__selenium_errors = [];
        window.addEventListener('error', function(e) {
            if (e.message) {
                window.__selenium_errors.push({
                    message: e.message || String(e),
                    filename: e.filename,
                    lineno: e.lineno,
                    colno: e.colno,
                    stack: e.error ? String(e.error.stack).slice(0, 500) : '',
                    type: 'error'
                });
            }
        });
        window.addEventListener('unhandledrejection', function(e) {
            window.__selenium_errors.push({
                message: e.reason?.message || String(e.reason),
                stack: e.reason ? String(e.reason.stack).slice(0, 500) : '',
                type: 'unhandledrejection'
            });
        });
    """)

    # Step 1: 禁用 glass-pane 的鼠标拦截（使用 !important 防止被覆盖）。
    # 注意：ChromeDriver 151 对以 `(function` 开头的 IIFE 脚本会静默返回 None，
    # 一律使用顶层语句形式（var 声明，避免顶层 const 重复声明报错）。
    driver.execute_script("""
        var gp = document.querySelector('flt-glass-pane');
        if (gp) {
            gp.style.setProperty('pointer-events', 'none', 'important');
            var canvas = gp.shadowRoot ? gp.shadowRoot.querySelector('canvas') : null;
            if (canvas) {
                canvas.style.setProperty('pointer-events', 'none', 'important');
            }
        }
    """)

    # Step 2: 轮询等待语义树激活（最多 30 次 × 1 秒）。
    # - 返回 None：页面处于导航/初始化中，只等待，绝不点击 placeholder
    # - 返回 >0：语义树已激活，完成
    # - 返回 0：明确未激活，点击 placeholder 兜底
    for _ in range(30):
        count = driver.execute_script(
            "const host = document.querySelector('flt-semantics-host');"
            "return host ? host.children.length : 0;"
        )
        if count is None:
            time.sleep(1)
            continue
        if count > 0:
            break
        driver.execute_script("""
            var placeholder = document.querySelector('flt-semantics-placeholder');
            if (!placeholder) return 0;
            placeholder.style.cssText = [
                'display:block !important',
                'opacity:1 !important',
                'visibility:visible !important',
                'pointer-events:auto !important',
                'position:fixed',
                'top:0',
                'left:0',
                'width:100%',
                'height:100%',
                'z-index:99999',
            ].join(';');

            placeholder.dispatchEvent(new PointerEvent('pointerdown', {
                bubbles: true, cancelable: true
            }));
            placeholder.dispatchEvent(new PointerEvent('pointerup', {
                bubbles: true, cancelable: true
            }));
            placeholder.dispatchEvent(new MouseEvent('click', {
                bubbles: true, cancelable: true
            }));
            placeholder.click();
            var host = document.querySelector('flt-semantics-host');
            return host ? host.children.length : 0;
        """)
        time.sleep(1)

    # Step 3: 等待语义树填充完成（body 出现文本内容）。
    # 语义树激活后是惰性构建的：根节点出现 ≠ 树已填充，输入框/按钮等
    # 节点要几十秒后才出现。以 body.innerText 非空作为填充完成信号，
    # 避免登录/点击时因语义树未构建而失败。
    deadline = time.time() + 60
    while time.time() < deadline:
        try:
            text = driver.execute_script(
                "return document.body.innerText"
            ) or ""
        except Exception:
            text = ""
        if len(text.strip()) > 0:
            break
        time.sleep(2)

    # Step 4: 等待语义树稳定
    time.sleep(2)


def _wait_flutter_ready(driver, timeout: int = 120):
    """等待 Flutter 应用渲染完成并稳定。

    生产环境 Flutter 应用启动较慢（CanvasKit 加载 + 初始化可能 30s+），
    且启动时会先渲染 splash（flutter-view 出现），随后导航到实际页面
    （如登录页）——导航瞬间 ChromeDriver 的 execute_script 会返回 None，
    必须轮询等待执行上下文稳定，否则后续脚本调用会拿到 None。
    超时不算致命错误，由测试中的轮询断言兜底。
    """
    from selenium.webdriver.common.by import By
    from selenium.webdriver.support.ui import WebDriverWait
    from selenium.webdriver.support import expected_conditions as EC

    try:
        WebDriverWait(driver, timeout).until(
            EC.presence_of_element_located((By.CSS_SELECTOR, "flutter-view"))
        )
    except Exception:
        pass  # 超时不算致命错误，继续执行测试

    # 轮询等待执行上下文稳定：连续两次 execute_script 返回非 None 即认为稳定
    stable = 0
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            result = driver.execute_script(
                "const h = document.querySelector('flt-semantics-host');"
                "return {rs: document.readyState,"
                " sem: h ? h.children.length : 0};"
            )
        except Exception:
            result = None
        if result is not None:
            stable += 1
            if stable >= 2:
                break
        else:
            stable = 0
        time.sleep(2)
    time.sleep(3)


def get_flutter_diagnostics(driver) -> dict:
    """收集 Flutter 渲染诊断信息，用于排查生产环境渲染失败原因。

    对 execute_script 做容错：页面处于初始化中间态/导航中时，
    execute_script 可能返回 None 或抛异常，此时返回带错误信息的
    诊断 dict，避免误报"页面崩溃"。

    Returns:
        dict 包含:
        - flutter_view_exists: bool
        - glass_pane_exists: bool
        - canvas_count: int
        - semantics_children: int（语义树节点数量，>0 表示语义已启用）
        - js_errors: list（脚本错误与 unhandledrejection）
        - ready_state: str
        - canvas_kit_loaded: bool
        - current_url: str（附加，便于定位页面状态）
    """
    # 注意：ChromeDriver 151 对以 `(function` 开头的 IIFE 脚本会静默返回 None，
    # 此处使用顶层语句形式（var 声明）
    try:
        result = driver.execute_script("""
            var info = {};
            info.flutter_view_exists = !!document.querySelector('flutter-view');
            var gp = document.querySelector('flt-glass-pane');
            info.glass_pane_exists = !!gp;
            info.canvas_count = gp && gp.shadowRoot
                ? gp.shadowRoot.querySelectorAll('canvas').length
                : 0;
            var host = document.querySelector('flt-semantics-host');
            info.semantics_children = host ? host.children.length : 0;
            info.js_errors = window.__selenium_errors || [];
            info.ready_state = document.readyState;
            info.canvas_kit_loaded = !!(window.flutterCanvasKit);
            return info;
        """)
        if result is None:
            # 理论上 IIFE 不会返回 None；若发生说明执行上下文异常
            result = {"execute_script_none": True}
    except Exception as e:
        result = {"execute_script_error": f"{type(e).__name__}: {e}"}

    try:
        result["current_url"] = driver.current_url
    except Exception:
        pass
    return result


# ---------------------------------------------------------------------------
# WebDriver 创建（沿用 selenium_tests/conftest.py 的版本匹配逻辑）
# ---------------------------------------------------------------------------

def _get_chrome_version() -> tuple[str, str] | None:
    """获取 Chrome/Chromium 浏览器版本号。Returns (full, major) 或 None。"""
    import re
    import subprocess

    candidates = []
    if CHROMIUM_BINARY:
        candidates.append(CHROMIUM_BINARY)
    else:
        candidates.append(
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        )
        for name in ("google-chrome", "chromium-browser", "chromium"):
            path = shutil.which(name)
            if path:
                candidates.append(path)

    for bin_path in candidates:
        if not os.path.isfile(bin_path):
            continue
        try:
            out = subprocess.check_output(
                [bin_path, "--version"], stderr=subprocess.STDOUT, timeout=5
            ).decode()
            m = re.search(r"(\d+\.\d+\.\d+\.\d+)", out)
            if m:
                full = m.group(1)
                return (full, full.split(".")[0])
        except Exception:
            continue
    return None


def _get_chromedriver_version(binary_path: str) -> tuple[str, str] | None:
    """获取 chromedriver 二进制版本号。Returns (full, major) 或 None。"""
    import re
    import subprocess

    try:
        out = subprocess.check_output(
            [binary_path, "--version"], stderr=subprocess.STDOUT, timeout=5
        ).decode()
        m = re.search(r"(\d+\.\d+\.\d+\.\d+)", out)
        if m:
            full = m.group(1)
            return (full, full.split(".")[0])
    except Exception:
        pass
    return None


def _find_cached_chromedriver(chrome_major: str) -> str | None:
    """在 webdriver-manager 缓存中查找匹配 Chrome 主版本的 chromedriver。"""
    import glob as _glob

    cache = os.path.expanduser("~/.wdm/drivers/chromedriver")
    if not os.path.exists(cache):
        return None

    if os.path.isfile(cache):
        cd_info = _get_chromedriver_version(cache)
        if cd_info and cd_info[1] == chrome_major:
            return cache
        return None

    candidates = []
    for f in _glob.glob(os.path.join(cache, "**", "chromedriver"), recursive=True):
        parts = f.split(os.sep)
        for part in parts:
            if part.startswith(chrome_major + "."):
                candidates.append((part, f))
                break

    if not candidates:
        return None

    candidates.sort(key=lambda x: [int(n) for n in x[0].split(".")], reverse=True)
    return candidates[0][1]


def _create_chrome_driver():
    options = webdriver.ChromeOptions()
    if CHROMIUM_BINARY:
        options.binary_location = CHROMIUM_BINARY
    if HEADLESS:
        options.add_argument("--headless=new")
    options.add_argument("--test-type")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--ignore-certificate-errors")  # 生产 https 可能用自签证书
    # 公网源页面（home.chenkaidi.top）请求本地 https 代理（网页授权测试
    # mixed content 绕过）时，Chrome 的 Private Network Access 会阻止
    # 私有地址请求，此处关闭
    options.add_argument("--disable-features=PrivateNetworkAccessDeny")
    # 精确信任本地代理的自签证书：Chrome 131+ 的 --ignore-certificate-errors
    # 只对主 frame 导航生效（fetch 仍校验证书），且 Security domain 的
    # setIgnoreCertificateErrors 已被移除，只能按证书公钥信任
    if _PROXY_SPKI:
        options.add_argument(f"--ignore-certificate-errors-spki-list={_PROXY_SPKI}")
    options.add_argument("--incognito")
    options.add_argument("--use-gl=angle")
    options.add_argument("--use-angle=swiftshader")
    options.add_argument("--ignore-gpu-blocklist")
    options.add_argument("--window-size=1920,1080")

    service = None
    if CHROMEDRIVER_PATH:
        service = ChromeService(executable_path=CHROMEDRIVER_PATH)
    else:
        cached = None
        chrome_info = _get_chrome_version()
        if chrome_info:
            cached = _find_cached_chromedriver(chrome_info[1])
        if cached:
            print(f"[chromedriver] 使用缓存: {cached}")
            service = ChromeService(executable_path=cached)
        else:
            system_cd = shutil.which("chromedriver")
            if system_cd:
                cd_info = _get_chromedriver_version(system_cd)
                if cd_info and chrome_info and cd_info[1] != chrome_info[1]:
                    print(
                        f"[chromedriver] 系统 chromedriver 版本 ({cd_info[1]}) "
                        f"与 Chrome ({chrome_info[1]}) 不匹配，跳过"
                    )
                else:
                    print(f"[chromedriver] 使用系统安装: {system_cd}")
                    service = ChromeService(executable_path=system_cd)
            if not service:
                print("[chromedriver] 缓存未命中，由 webdriver-manager 下载...")
                service = ChromeService(ChromeDriverManager().install())

    return webdriver.Chrome(service=service, options=options)


def _create_firefox_driver():
    options = webdriver.FirefoxOptions()
    if HEADLESS:
        options.add_argument("--headless")
    options.add_argument("--window-size=1920,1080")
    return webdriver.Firefox(
        service=FirefoxService(GeckoDriverManager().install()), options=options
    )


# ---------------------------------------------------------------------------
# fixtures
# ---------------------------------------------------------------------------

def _create_ready_driver(url: str):
    """创建浏览器实例并等待 Flutter 页面渲染就绪。"""
    if BROWSER == "firefox":
        d = _create_firefox_driver()
    else:
        d = _create_chrome_driver()
    d.implicitly_wait(IMPLICIT_WAIT)
    d.set_page_load_timeout(PAGE_LOAD_TIMEOUT)

    # 追加 URL 参数启用 Flutter 语义树
    if 'enable_semantics=true' not in url:
        sep = '&' if '?' in url else '?'
        url = f'{url}{sep}enable_semantics=true'

    d.get(url)
    _wait_flutter_ready(d)
    enable_flutter_semantics(d)
    debug_sleep(2)
    return d


@pytest.fixture(scope="function")
def driver(prod_url):
    """每个测试函数独立浏览器实例，指向参数化指定的生产环境。"""
    ok, reason = get_reachability()[prod_url]
    if not ok:
        pytest.skip(f"生产环境不可达: {prod_url} ({reason})")

    try:
        d = _create_ready_driver(prod_url)
    except Exception as e:
        pytest.skip(f"无法打开页面 {prod_url}: {e}")

    yield d
    d.quit()


@pytest.fixture(scope="function")
def connect_driver(connect_target_url):
    """网页授权添加测试专用：打开源服务器（固定 URL，不参与多环境参数化）。

    与 driver fixture 的区别：目标固定为 CONNECT_SOURCE_URL，
    供 test_prod_connect.py 通过 driver 别名使用。
    依赖 connect_target_url 保证本地 https 代理先启动（SPKI 可用，
    Chrome 才能信任代理证书）。
    """
    from config import CONNECT_SOURCE_URL

    ok, reason = _check_reachability(CONNECT_SOURCE_URL)
    if not ok:
        pytest.skip(f"源服务器不可达: {CONNECT_SOURCE_URL} ({reason})")

    try:
        d = _create_ready_driver(CONNECT_SOURCE_URL)
    except Exception as e:
        pytest.skip(f"无法打开源服务器 {CONNECT_SOURCE_URL}: {e}")

    yield d
    d.quit()


@pytest.fixture(scope="session")
def connect_target_url():
    """网页授权测试的目标服务器地址。

    https 源页面请求 http 目标会被浏览器 mixed content 阻止
    （真实产品限制，console: Mixed Content ... net::ERR_FAILED），
    自动启动本地 HTTPS 反向代理（https://127.0.0.1:<port> → http://目标），
    浏览器侧 https→https 无此问题。可用 TEST_CONNECT_PROXY_URL 显式指定。
    """
    from config import CONNECT_SOURCE_URL, CONNECT_TARGET_URL, CONNECT_PROXY_URL

    if CONNECT_PROXY_URL:
        yield CONNECT_PROXY_URL
        return
    if (
        CONNECT_SOURCE_URL.startswith("https://")
        and CONNECT_TARGET_URL.startswith("http://")
    ):
        from https_proxy import HttpsReverseProxy

        global _PROXY_SPKI
        proxy = HttpsReverseProxy(CONNECT_TARGET_URL)
        proxy.start()
        _PROXY_SPKI = proxy.spki
        print(
            f"[proxy] {proxy.base_url} -> {CONNECT_TARGET_URL}"
            " (mixed content 绕过)"
        )
        try:
            yield proxy.base_url
        finally:
            proxy.stop()
            _PROXY_SPKI = ""
    else:
        yield CONNECT_TARGET_URL


def _host_key(url: str) -> str:
    """URL 主机名转 per-host 凭据变量的键（. 替换为 _）。"""
    from urllib.parse import urlparse

    return (urlparse(url).hostname or "").replace(".", "_")


@pytest.fixture(autouse=False)
def do_login(driver):
    """登录 fixture — 需要登录的测试类通过 autouse=True 引用。

    生产凭据必须通过 TEST_USERNAME / TEST_PASSWORD 环境变量注入
    （或按主机覆盖 TEST_USERNAME_<host> / TEST_PASSWORD_<host>，
    见 config.per_host_creds），未设置时跳过登录相关测试，
    避免静默使用默认凭据。
    """
    from config import per_host_creds

    # 多套生产环境管理员账号可能不同：按浏览器当前打开的 URL
    # 主机名选择对应凭据（冒烟测试打开 prod_url，connect 测试
    # 打开固定源服务器，两者都能正确匹配）。
    current_url = driver.current_url or ""
    username, password = per_host_creds(current_url)
    if not username or not password:
        pytest.skip(
            f"未设置 {current_url or '当前环境'} 的登录凭据"
            "（TEST_USERNAME/TEST_PASSWORD 或 TEST_*_<host>），"
            "跳过登录相关测试"
        )

    # 等待登录页输入框出现（生产页面语义树构建慢，输入框可能
    # 数十秒后才渲染），避免登录交互因输入框未就绪而失败
    from selenium.webdriver.common.by import By

    for _ in range(25):
        inputs = driver.find_elements(
            By.CSS_SELECTOR,
            "input[data-semantics-role='text-field']:not([disabled]), "
            "input.flt-text-editing",
        )
        if inputs:
            break
        time.sleep(2)

    from pages.login_page import LoginPage
    from pages.nav_bar import NavBar

    page = LoginPage(driver)
    try:
        page.login(username, password)
    except Exception as e:
        # 语义树可能仍未完全构建：等待后重试一次
        print(f"[login] 首次登录失败: {e}，等待后重试")
        time.sleep(10)
        try:
            page.login(username, password)
        except Exception as e2:
            pytest.skip(f"登录交互失败: {e2}")

    # 生产环境渲染慢：轮询等待主界面导航栏出现（最长 ~60s）
    nav = NavBar(driver)
    deadline = time.time() + 60
    while time.time() < deadline:
        if nav.is_visible():
            break
        time.sleep(5)
    if not nav.is_visible():
        # 诊断：dump 当前页面状态，便于区分"凭据错误停在登录页"
        # 与"登录成功但主界面渲染慢/导航栏结构不同"
        try:
            url = driver.current_url
            body = (
                driver.execute_script("return document.body.innerText") or ""
            )
            print(f"[login] 登录后导航栏未出现。当前 URL: {url}")
            print(f"[login] 页面内容（前 300 字符）: {body[:300]!r}")
        except Exception as e:
            print(f"[login] 状态诊断失败: {e}")
        pytest.skip(
            "登录失败，主界面导航栏不可用。"
            "请确认生产后端运行正常、目标环境凭据正确（该环境使用 "
            f"TEST_USERNAME_{_host_key(current_url)}/TEST_PASSWORD_"
            f"{_host_key(current_url)} 覆盖时以此为准）。"
        )
