from selenium.webdriver.common.by import By
from pages import BasePage


class ContainersPage(BasePage):
    """容器列表页面 Page Object — 通过 Flutter 语义树定位。"""

    PAGE_TITLE = (By.XPATH, '//flt-semantics[contains(@aria-label,"Containers") or contains(@aria-label,"容器") or contains(text(),"Containers") or contains(text(),"容器")]')

    def wait_loaded(self):
        self.wait_visible(*self.PAGE_TITLE)
