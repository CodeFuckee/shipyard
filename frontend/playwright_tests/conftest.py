"""Playwright E2E 测试 fixtures（issue #39）。

职责：
1. 启动 chromium（优先 CHROMIUM_EXECUTABLE 指定二进制，否则 Playwright
   自带 chromium；也可通过 TEST_CHANNEL 指定系统 Chrome channel）。
2. 访问应用时追加 ?enable_semantics=true，显式激活 Flutter Web 语义树
   （main.dart 已实现该 URL 参数），使 widget 以 DOM 元素暴露。
3. 注入 ConsoleErrorCollector，收集整个操作流程中的浏览器控制台报错
   （console.error / pageerror），供测试断言"全程控制台无报错"。
4. 提供已登录并停留在主界面的 ai_assistant_page fixture。
"""
import time

import pytest
from playwright.sync_api import sync_playwright

from config import (
    ACTION_TIMEOUT,
    BASE_URL,
    CHROMIUM_EXECUTABLE,
    HEADLESS,
    PAGE_LOAD_TIMEOUT,
    TEST_CHANNEL,
    TEST_PASSWORD,
    TEST_USERNAME,
)
from pages.ai_assistant_page import AiAssistantPage
from pages.login_page import LoginPage

# 已知引擎噪音列表：Flutter Web 引擎自身产生的无害报错（过滤后不算测试失败）。
#
# Flutter 3.35.x Web 引擎存在文本编辑连接缺陷（flutter/flutter#178619 /
# #187461，issue #34/#37 已做应用侧规避）：语义树模式 + 文本编辑时，
# 引擎 DefaultTextEditingStrategy.activeDomElement 的 domElement! 作用于
# null 崩溃。该崩溃在两种构建下表现为：
#   1. dart2js（main.dart.js）：pageerror 为 Error，堆栈特征含
#      "ayR.Pm"（textinput 通道更新 readonly 属性，本列表第 1 条）；
#   2. dart2wasm（main.dart.wasm）：pageerror 为裸 "Exception"（无堆栈），
#      且先打印 "Null check operator used on a null value" 引擎日志，
#      由 ConsoleErrorCollector.on_pageerror 的关联判定处理（第 2 条
#      仅作文档说明，不直接列 "Exception" 以免误过滤真实异常）。
#
# 除上述引擎缺陷噪音外，任何 console.error / pageerror 都判定为失败，
# 严格满足 issue #39「整个操作流程中控制台没有报错」的要求。
_KNOWN_ENGINE_NOISE = [
    # dart2js 构建：引擎 textinput readonly 更新内部 Error 的堆栈特征
    "ayr.pm (main.dart.js",
]


def _is_known_engine_noise(text: str) -> bool:
    """判断控制台报错文本是否属于已知引擎噪音（忽略大小写）。"""
    lowered = text.lower()
    return any(n.lower() in lowered for n in _KNOWN_ENGINE_NOISE)


class ConsoleErrorCollector:
    """收集浏览器控制台错误（console.error / pageerror）。

    过滤说明见模块顶部 _KNOWN_ENGINE_NOISE 注释。
    """

    def __init__(self):
        self._console = []
        self._pageerror = []
        # wasm 构建下引擎 null 崩溃日志标志：打印过
        # "Null check operator used on a null value" 后紧跟的裸
        # "Exception" pageerror 属于同一引擎缺陷（dart2wasm 异常无
        # JS 堆栈，只能靠关联日志识别），不单独计为测试失败。
        self._engine_null_crash_logged = False

    def on_console(self, msg):
        """console 消息回调：收集 type == error 的报错。

        同时监听引擎 null 崩溃日志（Flutter 3.35.x Web 已知缺陷，
        flutter/flutter#178619 / #187461），用于 wasm pageerror 关联判定。
        """
        if msg.type == "log" and "Null check operator used on a null value" in msg.text:
            self._engine_null_crash_logged = True
        if msg.type == "error":
            text = msg.text
            if not _is_known_engine_noise(text):
                self._console.append(f"[console.error] {text}")

    def on_pageerror(self, error):
        """pageerror 回调：收集页面未捕获的 JS 异常。"""
        text = str(error)
        stack = ""
        try:
            stack = getattr(error, "stack", "")
        except Exception:
            stack = ""
        if stack:
            text = f"{text}\n{stack}"
        else:
            # wasm 构建（dart2wasm）：异常无 JS 堆栈，为裸 "Exception"。
            # 若刚打印过引擎 null 崩溃日志，则属于已知引擎缺陷噪音
            # （应用侧已规避触发路径，见 issue #34/#37），过滤不计失败。
            if text.strip() == "Exception" and self._engine_null_crash_logged:
                self._engine_null_crash_logged = False
                return
        if not _is_known_engine_noise(text):
            self._pageerror.append(f"[pageerror] {text}")

    @property
    def errors(self):
        """已收集的全部控制台报错（已过滤已知引擎噪音）。"""
        return self._console + self._pageerror


@pytest.fixture(scope="session")
def playwright_instance():
    """会话级 Playwright 实例（负责管理浏览器进程）。"""
    with sync_playwright() as p:
        yield p


@pytest.fixture(scope="session")
def browser(playwright_instance):
    """会话级 chromium 浏览器实例。"""
    launch_kwargs = {"headless": HEADLESS}
    if CHROMIUM_EXECUTABLE:
        launch_kwargs["executable_path"] = CHROMIUM_EXECUTABLE
    if TEST_CHANNEL:
        launch_kwargs["channel"] = TEST_CHANNEL
    browser = playwright_instance.chromium.launch(**launch_kwargs)
    yield browser
    browser.close()


@pytest.fixture
def page(browser):
    """函数级页面：新 context + 新页面，避免测试间状态污染。"""
    context = browser.new_context(viewport={"width": 1280, "height": 800})
    pg = context.new_page()
    pg.set_default_timeout(ACTION_TIMEOUT)
    yield pg
    context.close()


@pytest.fixture
def console_errors(page):
    """控制台错误收集器：挂在 page 上，收集后返回给测试断言。"""
    collector = ConsoleErrorCollector()
    page.on("console", collector.on_console)
    page.on("pageerror", collector.on_pageerror)
    return collector


def _wait_flutter_ready(page):
    """等待 Flutter 应用渲染完成（flutter-view 元素出现 + 首帧缓冲）。"""
    page.wait_for_selector("flutter-view", timeout=PAGE_LOAD_TIMEOUT)
    time.sleep(2)


def _login(page):
    """执行登录：等待登录页输入框可见，填入测试账号并提交。"""
    login_page = LoginPage(page)
    login_page.do_login(TEST_USERNAME, TEST_PASSWORD)


@pytest.fixture
def ai_assistant_page(page, console_errors):
    """已登录并停留在主界面的 AI 助手页面对象。"""
    sep = "&" if "?" in BASE_URL else "?"
    page.goto(
        f"{BASE_URL}{sep}enable_semantics=true",
        wait_until="networkidle",
        timeout=PAGE_LOAD_TIMEOUT,
    )
    _wait_flutter_ready(page)
    _login(page)
    ai_page = AiAssistantPage(page, console_errors)
    ai_page.wait_for_selector(
        "flt-semantics[role='button']:has-text('AI Assistant: give Docker commands'), "
        "flt-semantics[role='button']:has-text('AI 助手：下达 Docker 操作指令')",
        timeout=PAGE_LOAD_TIMEOUT,
    )
    return ai_page
