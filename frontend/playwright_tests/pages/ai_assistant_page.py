"""AI 助手对话框 Page Object（issue #39）。

对应界面元素（Flutter Web 语义树，CanvasKit/skwasm 渲染）：
- 右上角 AI 助手按钮：main_tab_screen.dart 中 Key('agent_appbar_button')，
  语义树中为 role=button 且文本为 tooltip
  （英文 "AI Assistant: give Docker commands" / 中文 "AI 助手：下达 Docker 操作指令"）。
- AI 助手面板：agent_chat_screen.dart 中 Key('agent_chat_screen') / agent_side_panel，
  Web 端为右侧滑出边栏（showGeneralDialog）。
- 「打开新会话」按钮：Key('agent_new_session_button')，位于消息列表末尾
  （issue #36：空状态不渲染该按钮，需先产生一条消息）。
- 快捷指令（ActionChip）：Key('agent_quick_chip_status')，label 为
  "Container status" / "容器状态"，点击填入输入框（不直接发送）。
- 发送：输入框 onSubmitted 回车发送（发送按钮为纯图标，语义树中无文本，
  不直接定位；测试用 Enter 键触发发送）。
"""
import time

from pages.base_page import BasePage
from config import ACTION_TIMEOUT, debug_sleep

# 右上角 AI 助手按钮（中英文 tooltip）
AI_ASSISTANT_BUTTON = (
    "flt-semantics[role='button']:has-text('AI Assistant: give Docker commands'), "
    "flt-semantics[role='button']:has-text('AI 助手：下达 Docker 操作指令')"
)

# 「打开新会话」按钮（中英文文案）
NEW_SESSION_BUTTON = (
    "flt-semantics[role='button']:has-text('New chat'), "
    "flt-semantics[role='button']:has-text('打开新会话')"
)

# 快捷指令「容器状态」（中英文 label + 指令原文）
QUICK_CHIP_STATUS = (
    "flt-semantics[role='button']:has-text('Container status'), "
    "flt-semantics[role='button']:has-text('容器状态'), "
    "flt-semantics[role='button']:has-text('Show me the running status of all containers'), "
    "flt-semantics[role='button']:has-text('帮我查看所有容器的运行状态')"
)

# 发送按钮（纯图标，语义树中无文本，仅作参考；实际用 Enter 发送）
SEND_BUTTON = (
    "flt-semantics[role='button']:has-text('Send'), "
    "flt-semantics[role='button']:has-text('发送')"
)

# AI 助手输入框（textarea / input 语义镜像，排除 disabled 只读镜像）
INPUT_FIELD = (
    "textarea[data-semantics-role='text-field']:not([disabled]), "
    "input[data-semantics-role='text-field']:not([disabled])"
)

# 空状态文案（中英文各一份），用于判断面板是否打开 / 是否回到空状态
EMPTY_STATE_TEXT = (
    "flt-semantics:has-text('How can I help you?'), "
    "flt-semantics:has-text('有什么可以帮你')"
)


class AiAssistantPage(BasePage):
    """AI 助手右侧边栏（Web 端）。"""

    AI_ASSISTANT_BUTTON = AI_ASSISTANT_BUTTON
    NEW_SESSION_BUTTON = NEW_SESSION_BUTTON
    QUICK_CHIP_STATUS = QUICK_CHIP_STATUS
    SEND_BUTTON = SEND_BUTTON
    INPUT_FIELD = INPUT_FIELD
    EMPTY_STATE_TEXT = EMPTY_STATE_TEXT

    def __init__(self, page, console_errors):
        super().__init__(page)
        self._console_errors = console_errors

    @property
    def errors(self):
        """已收集的控制台报错列表（console.error / pageerror）。"""
        return self._console_errors.errors

    def open_panel(self, timeout: int = None):
        """点击右上角 AI 助手按钮打开面板，等待面板内容可见。"""
        self.wait_for_selector(AI_ASSISTANT_BUTTON, timeout=timeout)
        self.page.locator(AI_ASSISTANT_BUTTON).first.click()

        # 面板打开后：新会话按钮（有消息时）或空状态文案（空会话时）任一可见即可
        self.wait_for_selector(
            f"{NEW_SESSION_BUTTON}, {EMPTY_STATE_TEXT}",
            timeout=timeout or ACTION_TIMEOUT,
        )
        debug_sleep(0.5)

    def close_panel(self):
        """按 Escape 关闭右侧边栏（showGeneralDialog barrierDismissible）。"""
        self.page.keyboard.press("Escape")
        debug_sleep(0.5)

    @property
    def is_panel_open(self) -> bool:
        """面板是否处于打开状态（空状态文案可见即可判定）。"""
        return self.page.locator(EMPTY_STATE_TEXT).count() > 0

    def send_message(self, timeout: int = None):
        """点击快捷指令填入输入框，再回车发送一条消息（触发 SSE 回复）。

        说明：快捷指令点击后调用 _fillQuickCommand 填入 prompt（不直接发送），
        随后按 Enter 触发 onSubmitted -> _send()。发送按钮为纯图标按钮，
        语义树中无文本可定位，回车发送更可靠。

        时序保护：点击快捷指令后必须等待输入框真正填入内容（语义树
        刷新有延迟），否则过早按 Enter 会因输入框为空被 _send() 忽略。
        """
        self.wait_for_selector(QUICK_CHIP_STATUS, timeout=timeout)
        self.page.locator(QUICK_CHIP_STATUS).first.click()

        # 等待快捷指令内容真正填入输入框（语义树刷新有延迟）
        deadline = time.time() + (timeout or ACTION_TIMEOUT) / 1000.0
        while time.time() < deadline:
            if self.is_input_active and self.input_value.strip():
                break
            time.sleep(0.2)

        # 点击输入框确保编辑代理激活，再回车发送
        loc = self.page.locator(INPUT_FIELD).first
        if loc.count():
            loc.click()
        time.sleep(0.2)
        self.page.keyboard.press("Enter")

        # 发送成功后消息列表末尾出现「打开新会话」按钮
        self.wait_for_selector(
            NEW_SESSION_BUTTON, timeout=timeout or ACTION_TIMEOUT
        )
        debug_sleep(0.5)

    def open_new_session(self):
        """点击「打开新会话」按钮清空当前对话。"""
        self.wait_for_selector(NEW_SESSION_BUTTON)
        self.page.locator(NEW_SESSION_BUTTON).first.click()
        debug_sleep(0.5)

    @property
    def is_input_active(self) -> bool:
        """输入框是否可用（编辑代理存在且未禁用）。"""
        return self.page.locator(INPUT_FIELD).count() > 0

    @property
    def input_value(self) -> str:
        """读取输入框当前内容（草稿）。"""
        loc = self.page.locator(INPUT_FIELD).first
        if loc.count() == 0:
            return ""
        return loc.input_value()

    def type_input(self, text: str):
        """向输入框逐键输入草稿内容（不发送）。"""
        self.wait_for_selector(INPUT_FIELD)
        loc = self.page.locator(INPUT_FIELD).first
        loc.click()
        time.sleep(0.3)
        self.page.keyboard.type(text, delay=20)
        debug_sleep(0.5)

    @property
    def new_session_visible(self) -> bool:
        """「打开新会话」按钮当前是否可见。"""
        return self.page.locator(NEW_SESSION_BUTTON).count() > 0
