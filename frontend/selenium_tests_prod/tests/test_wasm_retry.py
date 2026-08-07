"""复现测试：慢速网络下 CanvasKit WASM 下载中断导致 Flutter 应用无法启动。

真实场景（实测 run_tests.sh 2 failed）：
http://10.0.0.122:8080 内网环境链路慢（CanvasKit WASM 约 6.7MB 下载仅
~227KB/s、ping 500ms+ 且波动），浏览器下载 WASM 中断，报
`WebAssembly compilation aborted: Network error: Response body loading
was aborted`，Flutter 引擎无法初始化（flutter-view 永不渲染），
test_flutter_app_renders / test_semantics_enabled 硬失败、登录测试连带
skip。同版本部署的 https://home.chenkaidi.top:507（快链路）全部通过。

当前行为（bug）：conftest 加载流程（_wait_flutter_ready /
enable_flutter_semantics）对 WASM 加载失败没有任何重试机制——
一次网络抖动就是永久失败，页面永远无法加载出来。

期望行为（修复目标）：检测到 WASM 加载失败（canvas_kit_loaded=False
且 JS 错误含 WebAssembly/aborted）时自动刷新页面重试，成功后继续。

测试使用 fake driver 模拟诊断序列，不依赖真实浏览器/网络。
"""

import pytest

from conftest import _load_flutter_with_retry, _wasm_load_failed

WASM_ERROR = (
    "WebAssembly compilation aborted: Network error: "
    "Response body loading was aborted"
)


class _FakeDriver:
    """模拟浏览器：execute_script 依次返回诊断序列，refresh 推进序列。

    用于单测重试逻辑，行为约定：
    - execute_script 返回当前序号的诊断 dict（形状同 get_flutter_diagnostics）
    - refresh() 使序号 +1（模拟刷新后页面状态变化）
    """

    def __init__(self, diag_sequence):
        self._diag_sequence = list(diag_sequence)
        self._i = 0
        self.refresh_count = 0
        self.get_count = 0
        self.last_url = ""

    @property
    def current_url(self):
        return self._diag_sequence[min(self._i, len(self._diag_sequence) - 1)][
            "current_url"
        ]

    def execute_script(self, script, *args):
        return self._diag_sequence[min(self._i, len(self._diag_sequence) - 1)]

    def refresh(self):
        self.refresh_count += 1
        self._i = min(self._i + 1, len(self._diag_sequence) - 1)

    def get(self, url):
        self.get_count += 1
        self.last_url = url

    def implicitly_wait(self, *a):
        pass

    def set_page_load_timeout(self, *a):
        pass

    def quit(self):
        pass


def _diag(canvas_kit_loaded=False, js_errors=()):
    """构造一条与 get_flutter_diagnostics 形状一致的诊断。"""
    return {
        "flutter_view_exists": False,
        "glass_pane_exists": False,
        "canvas_count": 0,
        "canvas_kit_loaded": canvas_kit_loaded,
        "semantics_children": 0,
        "js_errors": list(js_errors),
        "ready_state": "complete",
        "current_url": "http://test-env:8080/?enable_semantics=true",
    }


def _wasm_js_error(message=WASM_ERROR):
    return {"message": message, "type": "unhandledrejection", "stack": ""}


# ---------------------------------------------------------------------------
# _wasm_load_failed：WASM 加载失败检测
# ---------------------------------------------------------------------------


class TestWasmLoadFailedDetection:
    def test_detects_wasm_download_failure(self):
        """canvas_kit 未加载 + JS 错误含 WebAssembly/aborted → 判定失败。"""
        driver = _FakeDriver(
            [_diag(canvas_kit_loaded=False, js_errors=[_wasm_js_error()])]
        )
        assert _wasm_load_failed(driver) is True

    def test_detects_wasm_error_without_keyword_prefix(self):
        """错误消息即使不含 WebAssembly 关键字但含 aborted 也应识别。"""
        driver = _FakeDriver(
            [_diag(canvas_kit_loaded=False, js_errors=[_wasm_js_error(
                "NetworkError: aborted")])]
        )
        assert _wasm_load_failed(driver) is True

    def test_not_failure_when_canvaskit_loaded(self):
        """canvas_kit 已加载 → 即使有历史 JS 错误也不算 WASM 失败。"""
        driver = _FakeDriver(
            [_diag(canvas_kit_loaded=True, js_errors=[_wasm_js_error()])]
        )
        assert _wasm_load_failed(driver) is False

    def test_not_failure_with_unrelated_js_errors(self):
        """无 WASM 相关的 JS 错误（如普通脚本噪音）→ 不算 WASM 失败。"""
        driver = _FakeDriver(
            [_diag(canvas_kit_loaded=False, js_errors=[
                {"message": "ResizeObserver loop", "type": "error"}
            ])]
        )
        assert _wasm_load_failed(driver) is False

    def test_not_failure_with_empty_diagnostics(self):
        """诊断为空/无错误 → 不算 WASM 失败（等待即可）。"""
        driver = _FakeDriver([_diag(canvas_kit_loaded=False)])
        assert _wasm_load_failed(driver) is False


# ---------------------------------------------------------------------------
# _load_flutter_with_retry：WASM 失败自动刷新重试
# ---------------------------------------------------------------------------


class TestLoadFlutterWithRetry:
    def test_no_retry_when_load_succeeds(self, monkeypatch):
        """页面正常加载 → 不触发任何刷新。"""
        monkeypatch.setattr(
            "conftest._wait_flutter_ready", lambda driver, timeout=120: None
        )
        driver = _FakeDriver([_diag(canvas_kit_loaded=True)])
        _load_flutter_with_retry(driver, "http://test-env:8080")
        assert driver.get_count == 1
        assert driver.refresh_count == 0

    def test_retry_refreshes_and_recovers(self, monkeypatch):
        """WASM 下载中断一次 → 自动刷新 1 次，恢复后正常返回。"""
        monkeypatch.setattr(
            "conftest._wait_flutter_ready", lambda driver, timeout=120: None
        )
        driver = _FakeDriver(
            [
                _diag(canvas_kit_loaded=False, js_errors=[_wasm_js_error()]),
                _diag(canvas_kit_loaded=True),
            ]
        )
        _load_flutter_with_retry(driver, "http://test-env:8080")
        assert driver.refresh_count == 1
        # 恢复后不应继续刷新
        assert driver.refresh_count == 1

    def test_retry_after_multiple_failures(self, monkeypatch):
        """连续 2 次中断 → 刷新 2 次后恢复。"""
        monkeypatch.setattr(
            "conftest._wait_flutter_ready", lambda driver, timeout=120: None
        )
        driver = _FakeDriver(
            [
                _diag(canvas_kit_loaded=False, js_errors=[_wasm_js_error()]),
                _diag(canvas_kit_loaded=False, js_errors=[_wasm_js_error()]),
                _diag(canvas_kit_loaded=True),
            ]
        )
        _load_flutter_with_retry(driver, "http://test-env:8080")
        assert driver.refresh_count == 2

    def test_gives_up_after_max_retries(self, monkeypatch):
        """持续失败 → 最多刷新 max_retries 次后放弃（不无限重试）。"""
        monkeypatch.setattr(
            "conftest._wait_flutter_ready", lambda driver, timeout=120: None
        )
        always_fail = [
            _diag(canvas_kit_loaded=False, js_errors=[_wasm_js_error()])
        ] * 5
        driver = _FakeDriver(always_fail)
        _load_flutter_with_retry(driver, "http://test-env:8080", max_retries=3)
        assert driver.refresh_count == 3

    def test_custom_max_retries(self, monkeypatch):
        """max_retries 可配置（如 5 次）。"""
        monkeypatch.setattr(
            "conftest._wait_flutter_ready", lambda driver, timeout=120: None
        )
        always_fail = [
            _diag(canvas_kit_loaded=False, js_errors=[_wasm_js_error()])
        ] * 10
        driver = _FakeDriver(always_fail)
        _load_flutter_with_retry(driver, "http://test-env:8080", max_retries=5)
        assert driver.refresh_count == 5
