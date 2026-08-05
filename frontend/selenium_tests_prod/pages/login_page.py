import time

from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from pages import BasePage
from config import debug_sleep


class LoginPage(BasePage):
    """Flutter CanvasKit 登录页 — 通过键盘交互操作。"""

    # Flutter 文本编辑 input 选择器：
    # - 新版 CanvasKit 使用 data-semantics-role="text-field"（无 class 属性）
    # - 旧版 CanvasKit 使用 class="flt-text-editing"
    TEXT_EDITING_INPUT = (
        By.CSS_SELECTOR,
        "input[data-semantics-role='text-field']:not([disabled]), "
        "input.flt-text-editing"
    )
    USERNAME_SEMANTICS = (By.XPATH, '//flt-semantics[contains(@role,"text")]')
    USERNAME_INPUT = USERNAME_SEMANTICS
    LOGIN_BUTTON = (By.XPATH, '//flt-semantics[contains(@aria-label,"Login") or contains(@aria-label,"登录") or contains(text(),"Login") or contains(text(),"登录")]')

    @property
    def semantics_enabled(self) -> bool:
        """检查 Flutter 语义树是否已激活。"""
        count = self.driver.execute_script(
            'return document.querySelector("flt-semantics-host")?.children.length || 0;'
        )
        return count > 0

    def wait_for_semantics(self, timeout: int = 15):
        """等待 Flutter 语义树填充完成（最多 timeout 秒）。"""
        try:
            WebDriverWait(self.driver, timeout).until(
                lambda d: d.execute_script(
                    'return document.querySelector("flt-semantics-host")?.children.length > 0;'
                )
            )
        except Exception:
            pass  # 非致命：测试可在无语义树时回退到其他验证方式

    def _focus_first_textfield(self):
        """点击第一个 Flutter 文本字段使其获得焦点，创建 input.flt-text-editing 元素。"""
        # 策略 1: 通过语义树点击文本框（语义树已激活时最快）
        selectors = [
            '//flt-semantics[@role="textbox"]',
            '//flt-semantics[contains(@role, "text")]',
            '//flt-semantics[contains(@aria-label, "Username") or contains(@aria-label, "用户名")]',
        ]
        for xpath in selectors:
            try:
                el = self.driver.find_element(By.XPATH, xpath)
                self.driver.execute_script("""
                    arguments[0].scrollIntoView(true);
                    arguments[0].click();
                    arguments[0].dispatchEvent(new MouseEvent("click", {bubbles: true}));
                    arguments[0].dispatchEvent(new PointerEvent("pointerdown", {bubbles: true}));
                    arguments[0].dispatchEvent(new PointerEvent("pointerup", {bubbles: true}));
                """, el)
                time.sleep(1)
                return
            except Exception:
                continue

        # 策略 2: 在 canvas 上真实点击用户名输入框位置（页面上方中央约 35%）。
        # JS dispatchEvent 对 Flutter 无效，改用 CDP 真实鼠标事件。
        try:
            rect = self.driver.execute_script("""
                var gp = document.querySelector('flt-glass-pane');
                var canvas = gp && gp.shadowRoot
                    ? gp.shadowRoot.querySelector('canvas') : null;
                if (!canvas) return null;
                var r = canvas.getBoundingClientRect();
                return {left: r.left, top: r.top, width: r.width, height: r.height};
            """)
            if rect:
                self.click_flutter_point(
                    rect["left"] + rect["width"] * 0.5,
                    rect["top"] + rect["height"] * 0.35,
                )
            time.sleep(1)
        except Exception:
            pass

        # 策略 3: 回退到 glass-pane 中心偏上位置的真实点击
        try:
            rect = self.driver.execute_script("""
                var gp = document.querySelector('flt-glass-pane');
                if (!gp) return null;
                var r = gp.getBoundingClientRect();
                return {left: r.left, top: r.top, width: r.width, height: r.height};
            """)
            if rect:
                self.click_flutter_point(
                    rect["left"] + rect["width"] / 2,
                    rect["top"] + rect["height"] * 0.3,
                )
            time.sleep(1)
        except Exception:
            pass

    def _get_active_input(self):
        """获取当前活跃的 Flutter 文本编辑 input 元素。

        优先通过 document.activeElement 获取当前获得焦点的 input，
        若没有焦点 input 则尝试点击文本字段使其获得焦点。
        """
        # Step 1: 检查当前获得焦点的元素
        active = self.driver.execute_script("""
            const el = document.activeElement;
            if (el && el.tagName === 'INPUT' && (
                el.getAttribute('data-semantics-role') === 'text-field' ||
                el.classList.contains('flt-text-editing')
            )) {
                return true;
            }
            return false;
        """)
        if active:
            return self.driver.switch_to.active_element

        # Step 2: 查找已有的非禁用 input
        inputs = self.driver.find_elements(*self.TEXT_EDITING_INPUT)
        if inputs:
            # 点击第一个可交互的 input 使其获得焦点
            try:
                inputs[0].click()
                time.sleep(0.3)
                return self.driver.switch_to.active_element
            except Exception:
                return inputs[0]

        # Step 3: 尝试聚焦文本字段（点击 canvas / 语义节点）
        self._focus_first_textfield()

        # Step 4: 等待 input 出现（最长 10 秒，适应 CI 慢速渲染）
        try:
            WebDriverWait(self.driver, 10).until(
                EC.presence_of_element_located(self.TEXT_EDITING_INPUT)
            )
        except Exception:
            pass

        inputs = self.driver.find_elements(*self.TEXT_EDITING_INPUT)
        if not inputs:
            # 最后尝试：按 Tab 键切换到第一个输入框
            try:
                body = self.driver.find_element(By.TAG_NAME, "body")
                body.send_keys(Keys.TAB)
                time.sleep(0.5)
                inputs = self.driver.find_elements(*self.TEXT_EDITING_INPUT)
            except Exception:
                pass

        if not inputs:
            raise Exception(
                "找不到 Flutter 文本编辑 input。"
                "可能原因: (1) 语义树未启用 (2) 页面未完全渲染 (3) CanvasKit 未初始化。"
            )
        return inputs[0]

    def enter_username(self, username: str):
        debug_sleep(1)
        inp = self._get_active_input()
        inp.clear()
        inp.send_keys(username)
        debug_sleep(1.5)

    def enter_password(self, password: str):
        inp = self._get_active_input()
        inp.send_keys(Keys.TAB)
        time.sleep(0.3)
        debug_sleep(1)
        inp = self._get_active_input()
        inp.clear()
        inp.send_keys(password)
        debug_sleep(1.5)

    def click_login(self):
        debug_sleep(1)
        inp = self._get_active_input()
        inp.send_keys(Keys.ENTER)
        debug_sleep(2)

    def login(self, username: str, password: str):
        self.enter_username(username)
        time.sleep(0.5)
        self.enter_password(password)
        time.sleep(0.5)
        self.click_login()
