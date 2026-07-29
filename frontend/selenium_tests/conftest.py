import os
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
from config import BASE_URL, MOCK_BACKEND_URL, IMPLICIT_WAIT, PAGE_LOAD_TIMEOUT, BROWSER, HEADLESS, TEST_USERNAME, TEST_PASSWORD, CHROMIUM_BINARY, CHROMEDRIVER_PATH

# 底部导航标签名，供所有测试复用
TAB_NAMES = ["Dashboard", "Containers", "Resources", "Settings"]


def _is_server_reachable(url: str, timeout: int = 3) -> bool:
    try:
        parsed = urlparse(url)
        host = parsed.hostname or "localhost"
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        s = socket.create_connection((host, port), timeout=timeout)
        s.close()
        return True
    except Exception:
        return False


def _try_http(url: str, timeout: int = 5) -> bool:
    try:
        req = urllib.request.Request(url, method="GET")
        urllib.request.urlopen(req, timeout=timeout)
        return True
    except Exception:
        return False


def enable_flutter_semantics(driver):
    """启用 Flutter 无障碍语义树，使 CanvasKit 应用的 widget 可通过 DOM 访问。

    当 URL 中包含 ?enable_semantics=true 时，Flutter 应用会在加载时自动启用语义树，
    此函数作为额外的安全网：如果程序化启用因任何原因未生效，
    则通过点击 flt-semantics-placeholder 手动激活。
    """
    from selenium.webdriver.common.by import By
    from selenium.webdriver.support.ui import WebDriverWait
    from selenium.webdriver.support import expected_conditions as EC

    # Step 0: 注入浏览器端诊断脚本，捕获 JS 错误便于排查
    driver.execute_script("""
        window.__selenium_errors = [];
        window.addEventListener('error', function(e) {
            window.__selenium_errors.push({
                message: e.message || String(e),
                filename: e.filename,
                lineno: e.lineno,
                colno: e.colno,
                type: 'error'
            });
        });
        window.addEventListener('unhandledrejection', function(e) {
            window.__selenium_errors.push({
                message: e.reason?.message || String(e.reason),
                type: 'unhandledrejection'
            });
        });
    """)

    # Step 1: 禁用 glass-pane 的鼠标拦截（使用 !important 防止被覆盖）
    driver.execute_script("""
        (function() {
            const gp = document.querySelector('flt-glass-pane');
            if (gp) {
                gp.style.setProperty('pointer-events', 'none', 'important');
                const canvas = gp.shadowRoot?.querySelector('canvas');
                if (canvas) {
                    canvas.style.setProperty('pointer-events', 'none', 'important');
                }
            }
        })();
    """)

    # Step 2: 检查语义树是否已激活（URL 参数 ?enable_semantics=true 自动激活）
    # 如果语义树已有内容，无需等待/点击 placeholder
    initial_children = driver.execute_script("""
        const host = document.querySelector('flt-semantics-host');
        return host ? host.children.length : 0;
    """)
    semantics_already_active = initial_children > 0

    if not semantics_already_active:
        # Step 3: 等待 placeholder 出现在 DOM 中（最多 5 秒）
        try:
            WebDriverWait(driver, 5).until(
                EC.presence_of_element_located(
                    (By.CSS_SELECTOR, "flt-semantics-placeholder")
                )
            )
        except Exception:
            pass  # 即使超时也继续

        # Step 4: 点击 placeholder 直到语义树有内容（最多 30 次 × 0.5 秒 = 15 秒）
        for _ in range(30):
            count = driver.execute_script("""
                return (function() {
                    const placeholder = document.querySelector('flt-semantics-placeholder');
                    if (placeholder) {
                        // 确保 placeholder 完全可见和可点击
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

                        // Flutter CanvasKit 监听 pointer 事件（非 click），同时发送多种事件确保兼容
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
                    }
                    const host = document.querySelector('flt-semantics-host');
                    return host ? host.children.length : 0;
                })();
            """)
            if count and count > 0:
                break
            time.sleep(0.5)

    # Step 5: 等待语义树稳定
    time.sleep(2)


def _wait_flutter_ready(driver, timeout: int = 60):
    """等待 Flutter 应用渲染完成（flutter-view 元素出现）。"""
    from selenium.webdriver.common.by import By
    from selenium.webdriver.support.ui import WebDriverWait
    from selenium.webdriver.support import expected_conditions as EC

    try:
        WebDriverWait(driver, timeout).until(
            EC.presence_of_element_located((By.CSS_SELECTOR, "flutter-view"))
        )
        time.sleep(3)
    except Exception:
        pass  # 超时不算致命错误，继续执行测试


def get_flutter_diagnostics(driver) -> dict:
    """收集 Flutter 渲染诊断信息，用于 CI 环境下排查渲染失败原因。

    Returns:
        dict 包含以下键:
        - flutter_view_exists: bool，flutter-view 元素是否存在
        - glass_pane_exists: bool，flt-glass-pane 元素是否存在
        - canvas_count: int，canvas 元素数量
        - semantics_children: int，语义树节点数量
        - js_errors: list，收集到的 JavaScrip t错误
        - flutter_ready_state: str，document.readyState
        - canvas_kit_loaded: bool，window.flutterCanvasKit 是否可用
    """
    result = driver.execute_script("""
        (function() {
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

            // 检查 flutterCanvasKitLoaded promise 状态
            if (window.flutterCanvasKitLoaded) {
                window.flutterCanvasKitLoaded.then(function(ck) {
                    window.__ck_ok = true;
                }).catch(function(e) {
                    window.__ck_error = e ? (e.message || String(e)) : 'unknown';
                });
            }
            info.ck_load_ok = window.__ck_ok || false;
            info.ck_load_error = window.__ck_error || null;

            return info;
        })();
    """)
    if result is None:
        return {
            "flutter_view_exists": False,
            "glass_pane_exists": False,
            "canvas_count": 0,
            "semantics_children": 0,
            "js_errors": ["execute_script returned None"],
            "ready_state": "unknown",
            "canvas_kit_loaded": False,
            "ck_load_ok": False,
            "ck_load_error": "execute_script failed",
        }
    return result


def _get_chrome_version() -> tuple[str, str] | None:
    """获取 Chrome/Chromium 浏览器版本号。
    Returns (full_version, major_version) 或 None。
    """
    import subprocess
    import shutil

    candidates = []
    if CHROMIUM_BINARY:
        candidates.append(CHROMIUM_BINARY)
    else:
        # macOS
        candidates.append(
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        )
        # Linux
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
            import re
            m = re.search(r"(\d+\.\d+\.\d+\.\d+)", out)
            if m:
                full = m.group(1)
                major = full.split(".")[0]
                return (full, major)
        except Exception:
            continue
    return None


def _get_chromedriver_version(binary_path: str) -> tuple[str, str] | None:
    """获取 chromedriver 二进制文件的版本号。
    Returns (full_version, major_version) 或 None。
    """
    import subprocess
    import re

    try:
        out = subprocess.check_output(
            [binary_path, "--version"], stderr=subprocess.STDOUT, timeout=5
        ).decode()
        m = re.search(r"(\d+\.\d+\.\d+\.\d+)", out)
        if m:
            full = m.group(1)
            major = full.split(".")[0]
            return (full, major)
    except Exception:
        pass
    return None


def _find_cached_chromedriver(chrome_major: str) -> str | None:
    """在 webdriver-manager 缓存中查找匹配 Chrome 主版本的 chromedriver。
    Returns chromedriver 路径或 None。
    """
    import glob as _glob

    cache = os.path.expanduser("~/.wdm/drivers/chromedriver")
    if not os.path.exists(cache):
        return None

    # 新版 webdriver-manager (v4+): chromedriver 是直接的二进制文件
    if os.path.isfile(cache):
        cd_info = _get_chromedriver_version(cache)
        if cd_info and cd_info[1] == chrome_major:
            return cache
        return None

    # 旧版 webdriver-manager: chromedriver/<version>/<platform>/chromedriver
    if not os.path.isdir(cache):
        return None

    candidates = []
    for f in _glob.glob(
        os.path.join(cache, "**", "chromedriver"), recursive=True
    ):
        # 文件名如: .../148.0.7778.181/chromedriver-mac-arm64/chromedriver
        parts = f.split(os.sep)
        for part in parts:
            if part.startswith(chrome_major + "."):
                candidates.append((part, f))
                break

    if not candidates:
        return None

    # 取版本号最高的
    candidates.sort(key=lambda x: [int(n) for n in x[0].split(".")], reverse=True)
    return candidates[0][1]


def _create_chrome_driver(base_url: str = ""):
    options = webdriver.ChromeOptions()
    if CHROMIUM_BINARY:
        options.binary_location = CHROMIUM_BINARY
    if HEADLESS:
        options.add_argument("--headless=new")
    options.add_argument("--test-type")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--ignore-certificate-errors")
    options.add_argument("--incognito")
    # Docker 无 GPU 环境下的 WebGL 软件渲染策略：
    # --use-gl=angle + --use-angle=swiftshader：使用 Chromium 内置的
    # SwiftShader CPU 软件渲染器，通过 ANGLE 层提供 WebGL 支持。
    # SwiftShader 是 Chromium 自带的，无需外部 Mesa/EGL 系统库，
    # 在无 GPU 的 Docker 容器中比 --use-gl=egl（依赖 Mesa llvmpipe）
    # 更可靠。
    # --ignore-gpu-blocklist: 防止 Chromium 将软件渲染器列入黑名单。
    # 不添加 --disable-gpu：该标志会完全禁用 GPU 进程，阻止 SwiftShader 加载。
    options.add_argument("--use-gl=angle")
    options.add_argument("--use-angle=swiftshader")
    options.add_argument("--ignore-gpu-blocklist")
    options.add_argument("--window-size=1920,1080")

    service = None
    if CHROMEDRIVER_PATH:
        service = ChromeService(executable_path=CHROMEDRIVER_PATH)
    else:
        # 优先从缓存加载匹配版本，避免网络请求
        cached = None
        chrome_info = _get_chrome_version()
        if chrome_info:
            cached = _find_cached_chromedriver(chrome_info[1])
        if cached:
            print(f"[chromedriver] 使用缓存: {cached}")
            service = ChromeService(executable_path=cached)
        else:
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


@pytest.fixture(scope="session")
def base_url():
    return BASE_URL


@pytest.fixture(scope="session")
def server_reachable(base_url):
    """检查前端和 mock 后端是否都可达。"""
    frontend_ok = _is_server_reachable(base_url) and _try_http(base_url)
    mock_ok = _try_http(f"{MOCK_BACKEND_URL}/info")
    return frontend_ok and mock_ok


@pytest.fixture(scope="function")
def driver(base_url, server_reachable):
    if not server_reachable:
        pytest.skip(f"服务器不可达: {base_url}")

    if BROWSER == "firefox":
        d = _create_firefox_driver()
    else:
        d = _create_chrome_driver(base_url)
    d.implicitly_wait(IMPLICIT_WAIT)
    d.set_page_load_timeout(PAGE_LOAD_TIMEOUT)

    # 追加 URL 参数启用 Flutter 语义树，使得 flt-semantics 元素在页面加载时就生成，
    # 无需依赖点击 flt-semantics-placeholder 的竞态条件。
    url = base_url
    if 'enable_semantics=true' not in url:
        sep = '&' if '?' in url else '?'
        url = f'{url}{sep}enable_semantics=true'

    try:
        d.get(url)
    except Exception as e:
        d.quit()
        pytest.skip(f"无法打开页面 {url}: {e}")

    _wait_flutter_ready(d)
    enable_flutter_semantics(d)

    from config import debug_sleep
    debug_sleep(2)

    yield d
    d.quit()


@pytest.fixture(autouse=False)
def do_login(driver):
    """登录 fixture — 需要登录的测试类通过 autouse=True 引用。"""
    from pages.login_page import LoginPage
    from pages.nav_bar import NavBar

    page = LoginPage(driver)
    try:
        page.login(TEST_USERNAME, TEST_PASSWORD)
    except Exception as e:
        pytest.skip(f"登录交互失败: {e}")
    time.sleep(5)

    nav = NavBar(driver)
    if not nav.is_visible():
        pytest.skip(
            "登录失败，主界面导航栏不可用。"
            "请确认后端已运行且 TEST_USERNAME/TEST_PASSWORD 环境变量正确。"
        )
