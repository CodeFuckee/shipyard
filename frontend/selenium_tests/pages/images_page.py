from selenium.webdriver.common.by import By
from pages import BasePage


class ImagesPage(BasePage):
    """镜像列表页面 Page Object — 通过 Flutter 语义树定位。"""

    TAB_IMAGES = (By.XPATH, '//flt-semantics[contains(@aria-label,"Images") or contains(@aria-label,"镜像") or contains(text(),"Images") or contains(text(),"镜像")]')

    def wait_loaded(self):
        self.wait_visible(*self.TAB_IMAGES)

    def is_tab_visible(self) -> bool:
        return self.exists(*self.TAB_IMAGES)
