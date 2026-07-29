import time

from selenium.webdriver.common.by import By
from pages import BasePage
from config import debug_sleep


class NavBar(BasePage):
    """底部导航栏 Page Object — 通过 Flutter 语义树文本内容定位。"""

    TAB_XPATH_TEMPLATE = '//flt-semantics[contains(@aria-label,"{text}") or contains(text(),"{text}")]'

    TAB_MAP = {
        "Dashboard": ["Dashboard", "概览"],
        "Containers": ["Containers", "容器"],
        "Resources": ["Resources", "资源"],
        "Settings": ["Settings", "设置"],
        "概览": ["Dashboard", "概览"],
        "容器": ["Containers", "容器"],
        "资源": ["Resources", "资源"],
        "设置": ["Settings", "设置"],
    }

    def is_visible(self) -> bool:
        body_text = self.driver.execute_script("return document.body.innerText") or ""
        all_texts = {t for names in self.TAB_MAP.values() for t in names}
        return any(tab in body_text for tab in all_texts)

    def _find_tab_element(self, tab_name: str):
        names = self.TAB_MAP.get(tab_name, [tab_name])
        for name in names:
            xpath = self.TAB_XPATH_TEMPLATE.format(text=name)
            try:
                return self.driver.find_element(By.XPATH, xpath)
            except Exception:
                continue
        return None

    def tab_exists(self, tab_name: str) -> bool:
        return self._find_tab_element(tab_name) is not None

    def click_tab(self, tab_name: str):
        debug_sleep(1)
        el = self._find_tab_element(tab_name)
        if el:
            self.driver.execute_script("""
                arguments[0].scrollIntoView(true);
                arguments[0].click();
                arguments[0].dispatchEvent(new MouseEvent("click", {bubbles: true}));
                arguments[0].dispatchEvent(new PointerEvent("pointerdown", {bubbles: true}));
                arguments[0].dispatchEvent(new PointerEvent("pointerup", {bubbles: true}));
            """, el)
            time.sleep(0.5)
        debug_sleep(1.5)
