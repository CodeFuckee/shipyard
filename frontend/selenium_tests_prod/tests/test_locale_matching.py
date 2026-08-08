"""复现 CI 生产 connect 测试失败：settings_page 的中文 XPath 在英文 UI 上失配。

流水线 430/434 的 frontend:selenium_tests_prod 连续失败（connect 测试第
5/6 次），根因是 locale 不匹配：

- CI 容器 Chromium 未设置 --lang，以英文 locale 渲染 Flutter Web，
  诊断日志页面文本全英文（'Settings ... Default Server Active ... Show
  Copy Delete ... Change Password Logout ...'）
- settings_page.py 的定位 XPath 全部使用中文字符串（"添加服务器"、
  "服务器列表"、"网页授权添加"、"继续"、"确认"），在英文页面上全部失配，
  click_add_server 15 次重试后断言失败
- login_page.py 已做中英文双匹配（"Login"/"登录"），settings_page.py 未同步

本测试用 lxml 对 Flutter 语义树 DOM 做静态 XPath 求值复现：
修复前（纯中文 XPath）在英文 DOM 上 0 匹配 → 断言失败（复现 bug）；
修复后（中英双匹配）→ 匹配成功。同时保留中文 DOM 回归断言。
"""

from lxml import etree
from selenium import webdriver

from conftest import _apply_chrome_language, _apply_firefox_language
from pages.settings_page import SettingsPage

ADD_SERVER_BTN = SettingsPage.ADD_SERVER_BTN
CONNECT_ADD_ITEM = SettingsPage.CONNECT_ADD_ITEM
CONNECT_CONTINUE_BTN = SettingsPage.CONNECT_CONTINUE_BTN
CONNECT_CONFIRM_BTN = SettingsPage.CONNECT_CONFIRM_BTN
CONNECT_PROBE_FAILED = SettingsPage.CONNECT_PROBE_FAILED
MIXED_CONTENT_WARNING = SettingsPage.MIXED_CONTENT_WARNING
SERVER_LIST_XPATH = SettingsPage.SERVER_LIST_CONTAINER[1]
EMPTY_STATE_XPATH = SettingsPage.EMPTY_STATE_BTN[1]

# 英文 UI（CI Chromium 默认 locale）Flutter 语义树片段。
# 结构与 434 流水线 [diag-add-server] 诊断日志的英文页面一致。
# 空状态区域（主标题+副标题）合并为一个语义节点，模拟 Flutter 语义树
# 对 InkWell 内多个 Text 的合并行为。
EN_TREE = """<flt-semantics-view>
  <flt-semantics role="button" aria-label="Add Server"></flt-semantics>
  <flt-semantics role="button">Authorize Add</flt-semantics>
  <flt-semantics role="button">Continue</flt-semantics>
  <flt-semantics role="button">Confirm</flt-semantics>
  <flt-semantics>This server does not support authorized adding, please add manually</flt-semantics>
  <flt-semantics>Cannot connect to an http target from an https page (blocked as mixed content by the browser). Configure the target server with https</flt-semantics>
  <flt-semantics>Servers</flt-semantics>
  <flt-semantics>Add Server
Tap to add a Docker server</flt-semantics>
</flt-semantics-view>"""

# 中文 UI（本地开发环境默认）语义树片段。
ZH_TREE = """<flt-semantics-view>
  <flt-semantics role="button" aria-label="添加服务器"></flt-semantics>
  <flt-semantics role="button">网页授权添加</flt-semantics>
  <flt-semantics role="button">继续</flt-semantics>
  <flt-semantics role="button">确认</flt-semantics>
  <flt-semantics>该服务器不支持网页授权添加,请手动输入</flt-semantics>
  <flt-semantics>https 页面无法连接 http 目标（浏览器 mixed content 拦截）</flt-semantics>
  <flt-semantics>服务器列表</flt-semantics>
  <flt-semantics>添加服务器
点击添加 Docker 服务器</flt-semantics>
</flt-semantics-view>"""

def _count(xpath: str, tree: str) -> int:
    """在语义树 DOM 上静态求值 XPath，返回匹配节点数。"""
    return len(etree.fromstring(tree).xpath(xpath))


class TestEnUiMatching:
    """英文 UI（CI 环境）下 settings_page 各定位 XPath 必须能匹配。

    修复前这些断言全部失败——这正是流水线 430/434 connect 测试
    "多次尝试后仍未弹出添加服务器菜单"的根因。
    """

    def test_add_server_btn(self):
        assert _count(ADD_SERVER_BTN[1], EN_TREE) >= 1

    def test_connect_add_item(self):
        assert _count(CONNECT_ADD_ITEM[1], EN_TREE) >= 1

    def test_connect_continue_btn(self):
        assert _count(CONNECT_CONTINUE_BTN[1], EN_TREE) >= 1

    def test_connect_confirm_btn(self):
        assert _count(CONNECT_CONFIRM_BTN[1], EN_TREE) >= 1

    def test_probe_failed_hint(self):
        assert _count(CONNECT_PROBE_FAILED[1], EN_TREE) >= 1

    def test_mixed_content_warning(self):
        assert _count(MIXED_CONTENT_WARNING[1], EN_TREE) >= 1

    def test_server_list_container(self):
        assert _count(SERVER_LIST_XPATH, EN_TREE) >= 1

    def test_empty_state_btn(self):
        assert _count(EMPTY_STATE_XPATH, EN_TREE) >= 1


class TestBrowserLanguage:
    """浏览器必须强制中文 locale（CI 容器默认英文 → Flutter 英文 UI）。

    即使 XPath 已中英双匹配，仍强制中文 UI 保证行为确定性
    （页面文本断言、打码文案等也依赖 locale）。
    """

    def test_chrome_forced_zh_cn(self):
        options = webdriver.ChromeOptions()
        _apply_chrome_language(options)
        assert "--lang=zh-CN" in options.arguments
        prefs = options.experimental_options.get("prefs", {})
        assert "zh-CN" in prefs.get("intl.accept_languages", "")

    def test_firefox_forced_zh_cn(self):
        options = webdriver.FirefoxOptions()
        _apply_firefox_language(options)
        assert "zh-CN" in options.to_capabilities().get(
            "moz:firefoxOptions", {}).get("prefs", {}).get(
                "intl.accept_languages", "")


class TestZhUiMatching:
    """中文 UI（本地环境）回归保护：中英双匹配不能破坏原有中文定位。"""

    def test_add_server_btn(self):
        assert _count(ADD_SERVER_BTN[1], ZH_TREE) >= 1

    def test_connect_add_item(self):
        assert _count(CONNECT_ADD_ITEM[1], ZH_TREE) >= 1

    def test_connect_continue_btn(self):
        assert _count(CONNECT_CONTINUE_BTN[1], ZH_TREE) >= 1

    def test_connect_confirm_btn(self):
        assert _count(CONNECT_CONFIRM_BTN[1], ZH_TREE) >= 1

    def test_probe_failed_hint(self):
        assert _count(CONNECT_PROBE_FAILED[1], ZH_TREE) >= 1

    def test_mixed_content_warning(self):
        assert _count(MIXED_CONTENT_WARNING[1], ZH_TREE) >= 1

    def test_server_list_container(self):
        assert _count(SERVER_LIST_XPATH, ZH_TREE) >= 1

    def test_empty_state_btn(self):
        assert _count(EMPTY_STATE_XPATH, ZH_TREE) >= 1
