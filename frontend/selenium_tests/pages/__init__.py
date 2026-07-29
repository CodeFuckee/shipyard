from selenium.webdriver.remote.webdriver import WebDriver
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from config import IMPLICIT_WAIT


class BasePage:
    def __init__(self, driver: WebDriver):
        self.driver = driver
        self.wait = WebDriverWait(driver, IMPLICIT_WAIT)

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
