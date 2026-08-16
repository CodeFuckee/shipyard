"""Playwright 测试 Page Object 基类（issue #39）。

Flutter Web（CanvasKit / skwasm 模式）默认把界面渲染在 canvas 上，DOM 中
无可交互元素。测试通过在 URL 追加 ?enable_semantics=true 显式激活语义树
（main.dart 中 SemanticsBinding.instance.ensureSemantics()），使 widget
以 flt-semantics DOM 元素暴露，可按 role / aria-label / 文本定位。
"""
from playwright.sync_api import Page

from config import ACTION_TIMEOUT


class BasePage:
    """页面对象基类：统一持有 Playwright Page 实例。"""

    def __init__(self, page: Page):
        self.page = page

    def wait_for_selector(
        self, selector: str, timeout: int = None, state: str = "visible"
    ):
        """等待指定元素出现在 DOM 中（语义树元素）。

        Args:
            selector: CSS / 文本选择器（Playwright 语法）。
            timeout: 超时毫秒，默认 ACTION_TIMEOUT。
            state: 期望状态（visible / attached / hidden 等）。
        """
        return self.page.wait_for_selector(
            selector, timeout=timeout or ACTION_TIMEOUT, state=state
        )
