import time

from selenium.webdriver.remote.webdriver import WebDriver
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from config import IMPLICIT_WAIT


class BasePage:
    def __init__(self, driver: WebDriver):
        self.driver = driver
        self.wait = WebDriverWait(driver, IMPLICIT_WAIT)

    def click_flutter_point(self, x: float, y: float):
        """通过 CDP 在页面指定坐标产生真实鼠标点击。

        JS dispatchEvent 派发的事件 Flutter CanvasKit 不一定接收，
        改用 CDP Input.dispatchMouseEvent（浏览器级合成输入）。
        enable_flutter_semantics 禁用了 glass-pane 的 pointer-events，
        点击前先恢复 canvas 命中。
        """
        self.driver.execute_script("""
            var gp = document.querySelector('flt-glass-pane');
            if (gp) {
                gp.style.setProperty('pointer-events', 'auto', 'important');
                var canvas = gp.shadowRoot
                    ? gp.shadowRoot.querySelector('canvas') : null;
                if (canvas) {
                    canvas.style.setProperty('pointer-events', 'auto', 'important');
                }
            }
        """)
        for event_type in ("mousePressed", "mouseReleased"):
            self.driver.execute_cdp_cmd("Input.dispatchMouseEvent", {
                "type": event_type,
                "x": x,
                "y": y,
                "button": "left",
                "clickCount": 1,
            })
        time.sleep(1)

    def find(self, by: str, value: str):
        return self.driver.find_element(by, value)

    def find_all(self, by: str, value: str):
        return self.driver.find_elements(by, value)

    def wait_visible(self, by: str, value: str):
        return self.wait.until(EC.visibility_of_element_located((by, value)))

    def wait_clickable(self, by: str, value: str):
        return self.wait.until(EC.element_to_be_clickable((by, value)))

    def exists(self, by: str, value: str) -> bool:
        try:
            return self.driver.find_element(by, value).is_displayed()
        except Exception:
            return False

    @property
    def current_url(self):
        return self.driver.current_url

    @property
    def title(self):
        return self.driver.title
