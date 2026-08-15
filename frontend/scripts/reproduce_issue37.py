#!/usr/bin/env python3
"""issue #37 复现脚本：WASM 构建 + headless Chrome + 增强 mock 后端。

流程：启动增强 mock_backend（含 agent 端点：带历史消息与工具列表）
→ selenium（BiDi）打开页面 → 登录 → 点击右上角 AI 助手按钮打开聊天
对话框 → 收集 console 完整消息（wasm 异常）。

用法：
    python scripts/reproduce_issue37.py [--keep]   # --keep 保留后端进程
"""
import json
import os
import subprocess
import sys
import threading
import time

BASE_URL = "http://localhost:9000/?enable_semantics=true"
FRONTEND_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
MOCK_BACKEND_PATH = os.path.join(FRONTEND_DIR, "selenium_tests", "mock_backend.py")

# 增强 mock：带历史消息（含工具步骤）与工具列表，模拟生产真实数据
HISTORY_MESSAGES = [
    {"role": "user", "content": "帮我拉取 nginx 镜像"},
    {
        "role": "assistant",
        "content": "已拉取 nginx:alpine",
        "steps": [
            {
                "type": "step",
                "name": "docker_mirror_pull",
                "arguments": {"image": "nginx:alpine"},
            },
            {
                "type": "step_result",
                "name": "docker_mirror_pull",
                "result": "ok",
            },
        ],
    },
]
TOOLS_RESPONSE = {
    "skills": [
        {
            "name": "docker_mirror_pull",
            "description": "拉取单个镜像",
            "group": "镜像拉取",
            "parameters": {},
        },
        {
            "name": "docker_pull_from_file",
            "description": "批量拉取镜像",
            "group": "镜像拉取",
            "parameters": {},
        },
    ],
    "tools": [
        {
            "name": "list_containers",
            "description": "列出所有容器",
            "group": "容器",
            "parameters": {},
        },
        {
            "name": "container_status",
            "description": "查看容器状态",
            "group": "容器",
            "parameters": {},
        },
    ],
}


def load_mock_module():
    """动态导入 mock_backend 模块（避免污染 selenium 测试基础设施）。"""
    import importlib.util

    spec = importlib.util.spec_from_file_location("mock_backend", MOCK_BACKEND_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def start_mock_backend():
    """后台启动增强 mock 后端（静态文件 + Portainer API + agent 端点）。"""
    mb = load_mock_module()

    class EnhancedHandler(mb.MockHandler):
        """在 mock_backend 基础上补充 AI agent 端点（issue #37 复现用）。"""

        def do_GET(self):
            path = self.path.split("?")[0]
            if path == "/admin/agent/chat-history":
                self._send_json({"messages": HISTORY_MESSAGES})
            elif path == "/admin/agent/tools":
                self._send_json(TOOLS_RESPONSE)
            else:
                super().do_GET()

    server = mb.ThreadingHTTPServer(("0.0.0.0", 9000), EnhancedHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    for _ in range(60):
        try:
            import urllib.request

            urllib.request.urlopen("http://localhost:9000/info", timeout=2)
            return server
        except Exception:
            time.sleep(0.5)
    raise RuntimeError("mock backend 启动失败")


def create_driver():
    from selenium import webdriver
    from selenium.webdriver.chrome.service import Service as ChromeService

    options = webdriver.ChromeOptions()
    options.add_argument("--headless=new")
    options.add_argument("--test-type")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--window-size=1920,1080")
    options.add_argument("--use-gl=angle")
    options.add_argument("--use-angle=swiftshader")
    options.add_argument("--ignore-gpu-blocklist")
    options.enable_bidi = True
    return webdriver.Chrome(
        service=ChromeService("/usr/bin/chromedriver"), options=options
    )


def inject_error_collector(driver):
    driver.execute_script("""
        window.__selenium_errors = [];
        window.addEventListener('error', function(e) {
            window.__selenium_errors.push({
                message: e.message || String(e),
                filename: e.filename,
                lineno: e.lineno,
                type: 'error'
            });
        });
        window.addEventListener('unhandledrejection', function(e) {
            window.__selenium_errors.push({
                message: (e.reason && e.reason.message) || String(e.reason),
                type: 'unhandledrejection'
            });
        });
    """)


def click_semantics_node(driver, xpath):
    """对语义树节点派发完整事件序列（Flutter 语义树监听 pointer 事件）。"""
    from selenium.webdriver.common.by import By

    el = driver.find_element(By.XPATH, xpath)
    driver.execute_script("""
        const el = arguments[0];
        el.scrollIntoView(true);
        el.dispatchEvent(new PointerEvent('pointerdown', {bubbles: true, cancelable: true}));
        el.dispatchEvent(new PointerEvent('pointerup', {bubbles: true, cancelable: true}));
        el.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true}));
    """, el)


def login(driver):
    """键盘交互登录（复用 selenium_tests 的流程）。"""
    from selenium.webdriver.common.by import By
    from selenium.webdriver.common.keys import Keys
    from selenium.webdriver.support.ui import WebDriverWait

    WebDriverWait(driver, 60).until(
        lambda d: d.execute_script(
            'return document.querySelector("flutter-view") != null;'
        )
    )
    time.sleep(5)  # 等 wasm 加载 + 首帧
    WebDriverWait(driver, 60).until(
        lambda d: d.execute_script(
            'return (document.querySelector("flt-semantics-host")?.children.length || 0) > 0;'
        )
    )
    time.sleep(2)

    # 聚焦第一个输入框（用户名）
    for _ in range(10):
        inputs = driver.find_elements(
            By.CSS_SELECTOR,
            "input[data-semantics-role='text-field']:not([disabled]), input.flt-text-editing",
        )
        if inputs:
            break
        click_semantics_node(driver, '//flt-semantics[@role="textbox"]')
        time.sleep(1)
    else:
        raise RuntimeError("找不到用户名输入框")

    active = driver.switch_to.active_element
    active.send_keys("admin")
    time.sleep(1)
    active.send_keys(Keys.TAB)
    time.sleep(1)
    active = driver.switch_to.active_element
    active.send_keys("password")
    time.sleep(1)
    active.send_keys(Keys.ENTER)
    time.sleep(6)  # 等登录跳转 + 主界面渲染


def find_appbar_ai_button(driver):
    """找到右上角 AppBar 的 AI 助手按钮。

    AppBar actions 从右往左依次为：WS 状态图标、刷新按钮、AI 助手按钮。
    语义树中按钮无 aria-label（IconButton 无 label），按坐标筛选：
    顶部区域（top < 80）的按钮节点里，AI 按钮在刷新按钮左侧
    （left 最小的那个）。
    """
    rects = driver.execute_script("""
        const nodes = document.querySelectorAll('flt-semantics[role="button"]');
        const out = [];
        nodes.forEach(n => {
            const r = n.getBoundingClientRect();
            out.push({id: n.id, top: r.top, left: r.left});
        });
        return out;
    """)
    top_buttons = [r for r in rects if r["top"] < 80]
    if not top_buttons:
        return None
    top_buttons.sort(key=lambda r: r["left"])
    return driver.execute_script(
        "return document.getElementById(arguments[0]);", top_buttons[0]["id"]
    )


def main():
    keep = "--keep" in sys.argv
    server = start_mock_backend()
    driver = None
    try:
        driver = create_driver()

        # BiDi 捕获完整 console 消息（wasm 异常在普通 browser log 中被截断）
        messages = []
        driver.script.add_console_message_handler(lambda m: messages.append(m))
        driver.script.add_javascript_error_handler(lambda m: messages.append(("JSERR", m)))

        inject_error_collector(driver)
        driver.get(BASE_URL)
        login(driver)
        time.sleep(2)
        messages.clear()  # 清掉打开对话框前的消息

        btn = find_appbar_ai_button(driver)
        if btn is None:
            print("[FAIL] 未找到右上角 AI 助手按钮")
            return 1
        rect = driver.execute_script(
            "const r = arguments[0].getBoundingClientRect();"
            "return {top: r.top, left: r.left, w: r.width, h: r.height};",
            btn,
        )
        print(f"[INFO] AI 按钮位置: {rect}")
        node_id = driver.execute_script("return arguments[0].id;", btn)
        click_semantics_node(driver, '//flt-semantics[@id="{}"]'.format(node_id))
        time.sleep(6)  # 等滑入动画 + 自动聚焦 + 历史/工具加载

        print("=== 打开对话框后 console 消息 ===")
        null_check_found = False
        for m in messages:
            if isinstance(m, tuple):
                txt = str(m[1])[:400]
                print("JSERR:", txt)
                if "Null check" in txt or "WebAssembly.Exception" in txt:
                    null_check_found = True
            else:
                txt = str(m)[:400]
                if (
                    "wasm" in txt
                    or "Null" in txt
                    or "Exception" in txt
                    or "error" in txt.lower()
                    or "Failed" in txt
                ):
                    print("CONSOLE:", txt)
                    if "Null check" in txt:
                        null_check_found = True

        print()
        if null_check_found:
            print("[复现成功] 检测到 Null check 异常")
            return 0
        print("[未复现] 未检测到 Null check 异常")
        return 2
    finally:
        if driver:
            driver.quit()
        if not keep:
            server.shutdown()


if __name__ == "__main__":
    sys.exit(main())
