"""复现 connect 测试最后一步失败：服务器 URL 打码后主机名匹配失配。

流水线 436（job 2300）connect 测试走到最后一步失败：
'服务器列表未出现 https://127.0.0.1:43843，授权添加可能失败'。

根因：前端 settings_screen.dart _maskUrl 对服务器 URL 的主机名打码
（>5 字符时显示 前3+****+后2）：127.0.0.1 → 127****.1、10.0.0.122 →
10.****22。页面文本中不存在完整主机名，而测试 server_list_contains
用完整主机名匹配 innerText，必然匹配失败。current_server_host 解析
打码 URL 得到打码主机名，与完整主机名的断言同样失败。

（locale 修复让授权流程首次走通后才暴露此断言 bug：此前 connect 测试
一直卡在"添加服务器菜单"环节，从未执行到最后一步。）
"""

from pages.settings_page import masked_host, text_contains_host


class TestMaskedHostFormat:
    """masked_host 必须与前端 _maskUrl 的打码格式一致。"""

    def test_proxy_host(self):
        assert masked_host("127.0.0.1") == "127****.1"

    def test_intranet_host(self):
        assert masked_host("10.0.0.122") == "10.****22"

    def test_long_host(self):
        assert masked_host("home.chenkaidi.top") == "hom****op"

    def test_short_host_fully_masked(self):
        assert masked_host("abc") == "****"


class TestTextContainsHost:
    """text_contains_host 必须匹配打码后的页面文本（复现 bug）。"""

    def test_masked_proxy_host(self):
        # 授权添加成功后列表显示 https://127****.1:43843（打码）
        text = "Settings\nDefault Server Active https://127****.1:43843\nShow"
        assert text_contains_host(text, "127.0.0.1")

    def test_masked_intranet_host(self):
        text = "http://10.****22:8080"
        assert text_contains_host(text, "10.0.0.122")

    def test_full_host_unmasked(self):
        # 未打码场景（如 host 未在列表中显示）兼容完整匹配
        text = "http://10.0.0.122:8080"
        assert text_contains_host(text, "10.0.0.122")

    def test_short_host_full(self):
        text = "https://abc:8443"
        assert text_contains_host(text, "abc")


class TestCurrentServerHostComparison:
    """current_server_host 解析打码 URL 得到打码主机名，断言侧需对齐。"""

    def test_masked_hostname_matches_target(self):
        # 页面"当前使用"行解析出的主机名 = 打码形式
        parsed_hostname = "127****.1"
        assert parsed_hostname == masked_host("127.0.0.1")

    def test_masked_hostname_matches_target_intranet(self):
        parsed_hostname = "10.****22"
        assert parsed_hostname == masked_host("10.0.0.122")
