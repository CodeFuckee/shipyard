"""目标服务器授权页（/connect/authorize）— 纯 HTML 页面，非 Flutter。

由后端 app/routers/connect.py 渲染：登录表单（#loginBox）与
确认按钮（#confirmBox）二选一显示，JS 控制切换。
"""

import time

from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait


class ConnectAuthorizePage:
    """授权页交互：等待加载 → 判断登录态 → 登录（如需）→ 确认。"""

    def __init__(self, driver):
        self.driver = driver

    def wait_loaded(self, timeout: int = 30):
        """等待授权页渲染完成（#btnConfirm 或 #btnLogin 出现）。"""
        WebDriverWait(self.driver, timeout).until(
            lambda d: (
                d.find_elements(By.ID, "btnConfirm")
                or d.find_elements(By.ID, "btnLogin")
            )
        )
        time.sleep(1)

    def _box_visible(self, box_id: str) -> bool:
        """读取 #loginBox / #confirmBox 的 display 状态。"""
        try:
            visible = self.driver.execute_script(
                "var el = document.getElementById(arguments[0]);"
                "return !!el && el.style.display !== 'none';",
                box_id,
            )
            return bool(visible)
        except Exception:
            return False

    def needs_login(self) -> bool:
        """判断授权页是否需要登录（登录表单与确认按钮二选一）。

        页面刚跳转过来时 JS 尚在查询会话状态，轮询等待渲染完成。
        """
        deadline = time.time() + 15
        while time.time() < deadline:
            if self._box_visible("loginBox"):
                return True
            if self._box_visible("confirmBox"):
                return False
            time.sleep(1)
        # 兜底：都不可见时按需登录处理，由 login() 内的等待兜住
        return True

    def login(self, username: str, password: str):
        """在授权页登录目标服务器管理员账号，等待确认按钮出现。"""
        user = self.driver.find_element(By.ID, "username")
        user.clear()
        user.send_keys(username)
        pwd = self.driver.find_element(By.ID, "password")
        pwd.clear()
        pwd.send_keys(password)
        self.driver.find_element(By.ID, "btnLogin").click()

        # 登录成功（JS 异步）后确认按钮出现
        WebDriverWait(self.driver, 20).until(
            lambda d: self._box_visible("confirmBox")
        )
        time.sleep(1)

    def confirm(self):
        """点击"确认并添加"，后端 302 回跳源服务器。"""
        self.driver.find_element(By.ID, "btnConfirm").click()
        time.sleep(2)
