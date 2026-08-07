import time

from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait

from config import debug_sleep
from pages import BasePage


class SettingsPage(BasePage):
    """Settings 页 — 添加服务器与网页授权添加对话框。

    全部通过 Flutter 语义树定位（aria-label / 文本内容）。
    注意：ChromeDriver 151 对 IIFE 脚本会静默返回 None，
    本文件所有 execute_script 均为顶层语句形式。
    """

    # 注意：文本匹配用 contains(.,"...")（匹配整个节点文本含子节点），
    # contains(text(),"...") 只匹配直接文本节点，对话框/菜单内常失效。
    # "添加服务器"按钮（section header 右上角 / 空状态中央）
    ADD_SERVER_BTN = (
        By.XPATH,
        '//flt-semantics[contains(@aria-label,"添加服务器")'
        ' or contains(.,"添加服务器")]',
    )
    # 添加服务器菜单中的"网页授权添加"项（仅 Web 端显示）。
    # 实测 contains(text(),...) 能稳定定位菜单项按钮；
    # contains(.,...) 会匹配 alertdialog 容器导致点击无效。
    CONNECT_ADD_ITEM = (
        By.XPATH,
        '//flt-semantics[contains(@aria-label,"网页授权添加")'
        ' or contains(text(),"网页授权添加")]',
    )
    # 网页授权对话框的"继续"按钮
    CONNECT_CONTINUE_BTN = (
        By.XPATH,
        '//flt-semantics[contains(@aria-label,"继续")'
        ' or contains(text(),"继续")]',
    )
    # 探测成功后的"确认"按钮
    CONNECT_CONFIRM_BTN = (
        By.XPATH,
        '//flt-semantics[contains(@aria-label,"确认")'
        ' or contains(text(),"确认")]',
    )
    # 探测失败提示（语义树文本节点小查询，避免大范围查询关闭对话框）
    CONNECT_PROBE_FAILED = (
        By.XPATH,
        '//flt-semantics[contains(.,"不支持网页授权添加")]',
    )
    # mixed content 提前提示（https 源 + http 目标，输入 URL 时即显示）
    MIXED_CONTENT_WARNING = (
        By.XPATH,
        '//flt-semantics[contains(.,"mixed content")'
        ' or contains(.,"https 页面无法连接")]',
    )

    def _js_click(self, el):
        """通过 JS 点击语义树节点（与 NavBar 相同的方式）。"""
        self.driver.execute_script("""
            arguments[0].scrollIntoView(true);
            arguments[0].click();
            arguments[0].dispatchEvent(new MouseEvent("click", {bubbles: true}));
            arguments[0].dispatchEvent(new PointerEvent("pointerdown", {bubbles: true}));
            arguments[0].dispatchEvent(new PointerEvent("pointerup", {bubbles: true}));
        """, el)
        time.sleep(1)

    def click_add_server(self):
        """点击"添加服务器"，弹出添加方式菜单。

        服务器列表为空时是文本按钮（语义树可定位）；
        非空时是 section header 右侧的纯图标按钮（无语义文本），
        需按"服务器列表"标题行右端坐标点击。坐标点击受渲染时序影响
        可能失效，带重试与菜单可见性校验。

        生产环境（NAS/慢网络）服务器列表从后端 /admin/servers 加载
        可能 30s+，设置页在该窗口内只有 loading 骨架（无任何可点击
        元素）；实测重试 5 次 × 2s（11s 窗口）会偶发超时失败
        （流水线 430 连续两次 connect 测试失败），因此窗口放宽到
        15 次 × 2s。
        """
        debug_sleep(1)
        for _ in range(15):
            # 方案 1：语义树文本定位（空列表时可用）
            try:
                el = self.find(*self.ADD_SERVER_BTN)
                self._js_click(el)
                if self._add_menu_visible():
                    return
            except Exception:
                pass
            # 方案 2：坐标点击 header 右侧的 + 图标
            try:
                self._click_header_add_icon()
                if self._add_menu_visible():
                    return
            except Exception:
                pass
            time.sleep(2)
        raise AssertionError("多次尝试后仍未弹出添加服务器菜单")

    def _add_menu_visible(self) -> bool:
        """添加服务器菜单（网页授权添加项）是否已弹出。"""
        try:
            self.find(*self.CONNECT_ADD_ITEM)
            return True
        except Exception:
            return False

    def _click_header_add_icon(self):
        """定位"服务器列表"标题节点，点击其行右端的添加图标按钮。

        添加按钮（34x34 纯图标）位于 section header 行的最右端。
        注意："服务器列表"语义节点是**整个 section 容器**（宽度占满
        页面，高度含列表条目），不是 header 行本身——header 行在
        容器顶部（图标容器 34px + 间距），不同窗口宽度（如 CI 的
        1920 vs 本机 1280）下响应式布局会让行内位置偏移，固定
        y=top+17 可能落空。因此点击后若菜单未弹出，在 header 行
        高度范围内（0~40px）逐档调整 y 重试。
        """
        el = self.find(
            By.XPATH,
            '//flt-semantics[contains(@aria-label,"服务器列表")'
            ' or contains(text(),"服务器列表")]',
        )
        rect = self.driver.execute_script("""
            var r = arguments[0].getBoundingClientRect();
            return {left: r.left, top: r.top, right: r.right, bottom: r.bottom};
        """, el)
        x = rect["right"] - 22
        # header 行在 section 容器顶部，逐档尝试（0~40px 覆盖
        # 响应式布局下 header 行高度的变化）
        for offset in (17, 6, 28, 40, 0, 50):
            self.click_flutter_point(x, rect["top"] + offset)
            if self._add_menu_visible():
                return

    # 坐标点击复用 BasePage.click_flutter_point（CDP 真实鼠标事件）

    def click_connect_add(self) -> bool:
        """点击菜单中的"网页授权添加"，验证对话框打开。

        观察到的波动：点击菜单项后 onTap 执行（菜单关闭）但对话框
        可能未打开（Flutter 语义树模式下 showDialog 偶发失败）。
        返回 True 表示对话框已打开（"继续"按钮出现）；False 表示
        需要调用方重新打开菜单重试。
        """
        debug_sleep(1)
        from selenium.webdriver.support.ui import WebDriverWait
        from selenium.webdriver.support import expected_conditions as EC
        try:
            el = WebDriverWait(self.driver, 10).until(
                EC.presence_of_element_located(self.CONNECT_ADD_ITEM)
            )
        except Exception:
            print("[diag-connect] 菜单未弹出（add 点击失败）")
            return False  # 菜单未弹出
        time.sleep(3)  # 等菜单动画与语义布局完成

        try:
            self._js_click(el)
        except Exception:
            pass
        try:
            # 对话框"继续"按钮出现需要 5-10 秒（语义树构建慢）
            WebDriverWait(self.driver, 12).until(
                EC.presence_of_element_located(self.CONNECT_CONTINUE_BTN)
            )
            debug_sleep(1)
            return True
        except Exception:
            pass
        try:
            self._cdp_click_element(el)
        except Exception:
            pass
        try:
            WebDriverWait(self.driver, 12).until(
                EC.presence_of_element_located(self.CONNECT_CONTINUE_BTN)
            )
            debug_sleep(1)
            return True
        except Exception:
            pass
        print("[diag-connect] 菜单项点击后对话框未打开")
        return False

    def is_mixed_content_warning(self, timeout: int = 10) -> bool:
        """对话框是否显示 mixed content 提前提示（https 源 + http 目标）。

        提示由前端在输入 URL 时实时显示（onChanged 同步），但语义树
        构建有延迟，带轮询等待。返回 True 表示提示已出现。

        注意：Flutter 语义树在错误提示移除后可能残留旧节点（对话框
        打开时预填 http:// 产生的提示在改为 https 目标后仍留在语义
        树中，InputDecorator 错误文本过渡动画期间节点保留）。因此先
        校验输入框当前值：仅当输入仍是 http:// 目标时才认为提示真实
        有效（此时前端 isMixedContent=true，按钮必为禁用态）。
        """
        # 输入框当前值（与 enter_connect_url 相同的定位方式）
        val = self.driver.execute_script(
            "var el = document.querySelector("
            "  'input[data-semantics-role=\"text-field\"]');"
            "return el ? el.value : '';"
        ) or ""
        if val:
            from urllib.parse import urlparse
            scheme = (urlparse(val).scheme or "").lower()
            if scheme != "http":
                return False  # https 目标：语义树残留节点不算真实提示
        from selenium.webdriver.support.ui import WebDriverWait
        from selenium.webdriver.support import expected_conditions as EC
        try:
            WebDriverWait(self.driver, timeout).until(
                EC.presence_of_element_located(self.MIXED_CONTENT_WARNING)
            )
            return True
        except Exception:
            return False

    def continue_disabled(self) -> bool:
        """"继续"按钮是否处于禁用状态（mixed content 提示时前端禁用）。"""
        try:
            el = self.find(*self.CONNECT_CONTINUE_BTN)
            return el.get_attribute("aria-disabled") == "true"
        except Exception:
            return False

    def _cdp_click_element(self, el):
        """通过 CDP 在元素中心产生真实鼠标点击（比 JS dispatch 更可靠）。"""
        rect = self.driver.execute_script("""
            var r = arguments[0].getBoundingClientRect();
            return {left: r.left, top: r.top, right: r.right, bottom: r.bottom};
        """, el)
        x = (rect["left"] + rect["right"]) / 2
        y = (rect["top"] + rect["bottom"]) / 2
        for event_type in ("mousePressed", "mouseReleased"):
            self.driver.execute_cdp_cmd("Input.dispatchMouseEvent", {
                "type": event_type,
                "x": x,
                "y": y,
                "button": "left",
                "clickCount": 1,
            })
        time.sleep(1)

    def enter_connect_url(self, url: str):
        """在网页授权对话框中输入目标服务器 URL。

        重要：生产环境 Flutter 语义树在对话框打开后，频繁/大范围 DOM
        查询（querySelectorAll flt-semantics 遍历等）会导致对话框关闭
        （Flutter 语义树重建 bug）。因此对话框打开后尽量减少查询：
        仅等"继续"按钮出现一次，然后依赖 TextField autofocus 直接
        键盘输入，不做输入框轮询。
        """
        from selenium.webdriver.common.keys import Keys
        from selenium.webdriver.support.ui import WebDriverWait
        from selenium.webdriver.support import expected_conditions as EC

        # 0. 等待对话框打开（"继续"按钮出现，最多 15 秒）
        WebDriverWait(self.driver, 15).until(
            EC.presence_of_element_located(self.CONNECT_CONTINUE_BTN)
        )

        # 1. 等待 Flutter 创建文本输入框（TextField 聚焦后才创建 input
        #    元素，autofocus 在语义树模式下延迟生效）
        for _ in range(15):
            input_exists = self.driver.execute_script(
                "return !!document.querySelector("
                "  'input[data-semantics-role=\"text-field\"]');"
            )
            if input_exists:
                break
            time.sleep(1)

        # 2. 直接设置 input 值并派发 input 事件。
        #    Flutter web 监听 input 事件同步 controller；键盘删除预填
        #    http:// 会被 Flutter 拦截（Ctrl+A 无效），JS 设值直接替换。
        self.driver.execute_script("""
            var el = document.querySelector(
                'input[data-semantics-role="text-field"]');
            if (el) {
                el.value = arguments[0];
                el.dispatchEvent(new Event('input', {bubbles: true}));
            }
        """, url)

        # 3. 验证输入已写入且无残留预填（Flutter controller 同步需短暂时间）
        deadline = time.time() + 10
        while time.time() < deadline:
            val = self.driver.execute_script(
                "var el = document.querySelector("
                "  'input[data-semantics-role=\"text-field\"]');"
                "return el ? el.value : '';"
            ) or ""
            if val == url:
                break
            time.sleep(1)
        assert val == url, f"URL 输入未写入输入框 (当前值: {val!r})"
        debug_sleep(1)

    def click_connect_continue(self):
        """点击"继续"触发探测与注册（CDP 真实点击）。"""
        debug_sleep(1)
        el = self.find(*self.CONNECT_CONTINUE_BTN)
        self._cdp_click_element(el)

    def wait_probed(self, timeout: int = 45):
        """等待探测/注册完成。

        探测成功后对话框出现"确认"按钮；探测失败则出现回退提示。
        只使用小范围语义树查询（大范围查询会导致对话框关闭）。
        Returns:
            True 表示探测成功（可点确认），False 表示失败（对话框提示）。
        """
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                self.find(*self.CONNECT_CONFIRM_BTN)
                return True
            except Exception:
                pass
            try:
                self.find(*self.CONNECT_PROBE_FAILED)
                return False
            except Exception:
                pass
            time.sleep(2)
        # 临时诊断：超时时 dump 对话框状态
        try:
            state = self.driver.execute_script("""
                var out = {continue_btn: 0, confirm_btn: 0, failed: 0,
                           input_val: '', dialog: 0};
                var nodes = document.querySelectorAll('flt-semantics');
                for (var i = 0; i < nodes.length; i++) {
                    var t = (nodes[i].textContent || '');
                    var role = nodes[i].getAttribute('role') || '';
                    if (role === 'alertdialog') out.dialog++;
                    if (t.indexOf('继续') >= 0 && role === 'button') {
                        out.continue_btn++;
                    }
                    if (t.indexOf('确认') >= 0 && role === 'button') {
                        out.confirm_btn++;
                    }
                    if (t.indexOf('不支持网页授权') >= 0) out.failed++;
                }
                var el = document.querySelector(
                    'input[data-semantics-role="text-field"]');
                out.input_val = el ? el.value : '(无 input)';
                return out;
            """)
            print(f"[diag-probe] 超时状态: {state}")
        except Exception as e:
            print(f"[diag-probe] 诊断异常: {e}")
        raise AssertionError("探测超时：既未出现确认按钮也未出现失败提示")

    def click_connect_confirm(self):
        """点击"确认"，整页跳转到目标服务器授权页（CDP 真实点击）。"""
        debug_sleep(1)
        el = self.find(*self.CONNECT_CONFIRM_BTN)
        self._cdp_click_element(el)
        debug_sleep(2)

    def server_list_contains(self, host: str) -> bool:
        """Settings 服务器列表是否包含指定主机名（只读检查）。

        页面显示对 URL 做了打码（如 http://10.****22:8080），
        但主机名保持完整，用主机名匹配。
        """
        try:
            WebDriverWait(self.driver, 10).until(
                lambda d: host in (d.execute_script(
                    "return document.body.innerText"
                ) or "")
            )
            return True
        except Exception:
            return False

    def current_server_host(self) -> str:
        """读取"当前使用"标记的活动服务器主机名（打码 URL 中主机名完整）。"""
        text = self.driver.execute_script("return document.body.innerText") or ""
        import re
        m = re.search(r"当前使用[^\S\n]*([^\n]+)", text)
        if not m:
            return ""
        url = m.group(1).strip()
        from urllib.parse import urlparse
        host = urlparse(url if "://" in url else f"//{url}").hostname
        return host or ""
