"""登录页 Page Object（issue #39）。

Flutter Web（CanvasKit/skwasm）文本编辑机制：语义树中的
input[data-semantics-role='text-field'] 是只读展示镜像（disabled），
真正的输入发生在隐藏的 input.flt-text-editing 代理中。因此不能直接
fill()（只设 value 不触发 Flutter 事件），必须：
  1. 用真实鼠标点击输入框所在坐标，使其获得焦点（Flutter 创建编辑代理）
  2. 用键盘逐键输入（keyboard.type）
  3. Tab 切换字段、Enter / 点击登录按钮提交
"""
import time

from pages.base_page import BasePage
from config import ACTION_TIMEOUT, debug_sleep

# 用户名 / 密码输入框（语义树镜像 + 隐藏编辑代理）
TEXT_FIELD_SELECTOR = (
    "input[data-semantics-role='text-field']:not([disabled]), "
    "input.flt-text-editing"
)

# 登录按钮（中英文文案各一份，兼容默认英文 / 中文 locale）
LOGIN_BUTTON_SELECTOR = (
    "flt-semantics[role='button']:has-text('Login'), "
    "flt-semantics[role='button']:has-text('登录')"
)

# 从语义树中计算登录输入框的中心坐标（用户名、密码两行）。
# 返回 [{x, y}, {x, y}]，找不到时返回空列表。
_FIELD_COORDS_JS = """
    () => {
        const rows = Array.from(document.querySelectorAll('flt-semantics'))
            .map(el => {
                const r = el.getBoundingClientRect();
                return {x: Math.round(r.x), y: Math.round(r.y),
                        w: Math.round(r.width), h: Math.round(r.height)};
            })
            .filter(r => r.w > 300 && r.w < 500 && r.h >= 40 && r.h <= 60)
            // 同 y 的行去重（语义镜像重复暴露同一字段）
            .filter((r, i, arr) => arr.findIndex(a => Math.abs(a.y - r.y) < 3) === i)
            .sort((a, b) => a.y - b.y);
        return rows.slice(0, 2).map(r => ({
            x: Math.round(r.x + r.w / 2),
            y: Math.round(r.y + r.h / 2),
        }));
    }
"""

# 登录按钮中心坐标；找不到返回 None。
_LOGIN_BUTTON_JS = """
    () => {
        const btns = Array.from(document.querySelectorAll(
            'flt-semantics[role="button"]'
        ));
        const btn = btns.find(el => {
            const t = (el.textContent || '');
            const l = el.getAttribute('aria-label') || '';
            return t.includes('Login') || t.includes('登录')
                || l.includes('Login') || l.includes('登录');
        });
        if (!btn) return null;
        const r = btn.getBoundingClientRect();
        return {x: Math.round(r.x + r.width / 2),
                y: Math.round(r.y + r.height / 2)};
    }
"""


class LoginPage(BasePage):
    """Flutter CanvasKit 登录页。"""

    def _field_coords(self):
        """从语义树中计算登录输入框的中心坐标（用户名、密码两行）。

        返回 [{x, y}, {x, y}]，找不到时返回空列表。
        """
        return self.page.evaluate(_FIELD_COORDS_JS) or []

    def _login_button_center(self):
        """登录按钮中心坐标；找不到返回 None。"""
        return self.page.evaluate(_LOGIN_BUTTON_JS)

    @property
    def is_visible(self) -> bool:
        """登录页是否可见（用户名输入框镜像存在）。"""
        return self.page.locator(TEXT_FIELD_SELECTOR).count() > 0

    def do_login(self, username: str, password: str) -> None:
        """填写用户名密码并登录：真实鼠标点击字段 → 键盘输入 → 点击登录按钮。"""
        self.wait_for_selector(TEXT_FIELD_SELECTOR)

        fields = []
        # 语义树刷新有延迟，轮询等待两个输入框坐标都出现（最多 10 次）
        for _ in range(10):
            fields = self._field_coords()
            if len(fields) >= 2:
                break
            time.sleep(0.5)
        if len(fields) < 2:
            raise RuntimeError("未能从语义树中定位登录输入框坐标，请检查语义树是否已激活")

        # 1. 点击用户名输入框（真实鼠标点击，激活隐藏编辑代理）
        self.page.mouse.click(fields[0]["x"], fields[0]["y"])
        time.sleep(0.3)
        # 2. 逐键输入用户名
        self.page.keyboard.type(username, delay=30)
        debug_sleep(1)

        # 3. Tab 切换到密码输入框
        self.page.keyboard.press("Tab")
        time.sleep(0.3)
        # 4. 逐键输入密码
        self.page.keyboard.type(password, delay=30)
        debug_sleep(1)

        # 5. 优先点击登录按钮；找不到按钮时用 Enter 提交
        btn = self._login_button_center()
        if btn:
            self.page.mouse.click(btn["x"], btn["y"])
        else:
            self.page.keyboard.press("Enter")
        debug_sleep(1)
