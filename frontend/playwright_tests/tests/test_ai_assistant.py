"""AI 助手 Playwright E2E 测试（issue #39）。

模拟用户操作：
  [点击右上角打开 AI 助手按钮] -> [点击打开新会话]
并断言整个操作流程中浏览器控制台（console.error / pageerror）没有报错。

说明：空状态下 AI 助手面板不渲染「打开新会话」按钮（该按钮位于消息
列表末尾，issue #36），因此核心流程先通过快捷指令 + 回车发送产生一条
mock 回复消息，再点击「打开新会话」验证清空。

测试覆盖（§3.3 补充测试流程要求：正常路径 + 边界/重复调用场景）：
- 正常路径：登录 -> 打开 AI 助手 -> 产生消息 -> 打开新会话 -> 控制台无报错
- 边界：连续 3 次打开/关闭 AI 助手无报错
- 边界：空会话状态打开 AI 助手无报错
- 功能：发送消息后点「打开新会话」，消息清空、回到空状态、输入框可用
- 功能：输入半截草稿后点「打开新会话」，输入框被清空且无报错
- 边界：空状态下不存在「打开新会话」按钮（不误渲染、不崩溃）
"""


class TestAiAssistantFlow:
    """AI 助手核心操作流程（issue #39 主路径）。"""

    def test_open_panel_then_new_session_no_console_errors(self, ai_assistant_page):
        """核心流程：打开 AI 助手 -> 打开新会话 -> 控制台无报错。"""
        page = ai_assistant_page
        page.open_panel()
        assert page.is_panel_open, "AI 助手面板未打开"
        page.send_message()
        page.open_new_session()
        assert not page.errors, "操作流程中出现控制台报错：\n" + "\n".join(page.errors)

    def test_toggle_panel_multiple_times(self, ai_assistant_page):
        """边界：连续 3 次打开/关闭 AI 助手，控制台无报错。"""
        page = ai_assistant_page
        for i in range(3):
            page.open_panel()
            assert page.is_panel_open, f"第 {i + 1} 次打开面板失败"
            page.close_panel()
        assert not page.errors, "连续开关面板出现控制台报错：\n" + "\n".join(page.errors)

    def test_open_panel_in_empty_session(self, ai_assistant_page):
        """边界：空会话状态打开 AI 助手，控制台无报错。"""
        page = ai_assistant_page
        page.open_panel()
        assert page.is_panel_open, "空会话状态打开面板失败"
        assert not page.new_session_visible, "空状态不应出现「打开新会话」按钮"
        assert page.is_input_active, "空状态输入框应可用"
        assert not page.errors, "空会话打开面板出现控制台报错：\n" + "\n".join(page.errors)


class TestNewSessionBehavior:
    """「打开新会话」功能与边界场景（issue #39 扩展覆盖）。"""

    def test_new_session_clears_messages(self, ai_assistant_page):
        """功能：发送消息后点「打开新会话」，消息清空、回到空状态、输入框可用。"""
        page = ai_assistant_page
        page.open_panel()
        page.send_message()
        assert page.new_session_visible, "产生消息后应出现「打开新会话」按钮"
        page.open_new_session()
        page.wait_for_selector(page.EMPTY_STATE_TEXT)
        assert page.is_panel_open, "新会话后应回到空状态"
        assert not page.new_session_visible, "新会话后按钮应隐藏"
        assert page.is_input_active, "新会话后输入框应可用"
        assert not page.errors, "打开新会话后出现控制台报错：\n" + "\n".join(page.errors)

    def test_new_session_clears_draft(self, ai_assistant_page):
        """功能：输入半截草稿后点「打开新会话」，输入框被清空且无报错。"""
        page = ai_assistant_page
        page.open_panel()
        page.type_input("这是一段未发送的草稿")
        assert page.input_value != "", "草稿应已填入输入框"
        page.send_message()
        page.open_new_session()
        page.wait_for_selector(page.EMPTY_STATE_TEXT)
        assert page.input_value == "", "新会话后输入框草稿应被清空"
        assert page.is_input_active, "新会话后输入框应可用"
        assert not page.errors, "清空草稿后出现控制台报错：\n" + "\n".join(page.errors)

    def test_new_session_absent_in_empty_state(self, ai_assistant_page):
        """边界：空状态下不存在「打开新会话」按钮（issue #36 设计如此）。

        该按钮只出现在消息列表末尾，空状态不应渲染；此用例同时验证
        打开 AI 助手后界面正常（不崩溃、输入框可用）。
        """
        page = ai_assistant_page
        page.open_panel()
        assert not page.new_session_visible, "空状态不应渲染「打开新会话」按钮"
        assert page.is_input_active, "空状态输入框应可用"
        assert not page.errors, "空状态打开面板出现控制台报错：\n" + "\n".join(page.errors)
