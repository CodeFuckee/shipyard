"""measure_first_frame_load_time 测量逻辑单元测试（不依赖真实浏览器/网络）。

覆盖场景：
- 正常路径：首帧一次渲染成功，无重试，URL 自动追加语义树参数
- WASM 加载失败后刷新重试恢复
- WASM 持续失败时最多重试 max_retries 次后放弃
- 非 WASM 失败（页面异常/超时）不重试
- 刷新异常（页面导航中）终止重试
"""

import conftest
from conftest import measure_first_frame_load_time

WASM_ABORT = (
    "WebAssembly compilation aborted: Network error: "
    "Response body loading was aborted"
)


class _FakeDriver:
    """模拟浏览器：get() 重置到初始状态，refresh() 推进状态。

    execute_script 返回当前状态的诊断 dict（形状同
    get_flutter_diagnostics，get_flutter_diagnostics 只透传 execute_script
    的返回值）。
    """

    def __init__(self, states):
        self._states = list(states)
        self._i = 0
        self.get_count = 0
        self.refresh_count = 0
        self.last_url = ""
        self.refresh_errors = False  # 控制 refresh 是否抛异常

    def get(self, url):
        self.get_count += 1
        self.last_url = url
        self._i = 0

    def refresh(self):
        if self.refresh_errors:
            raise RuntimeError("navigation aborted")
        self.refresh_count += 1
        self._i = min(self._i + 1, len(self._states) - 1)

    def execute_script(self, script, *args):
        return dict(self._states[min(self._i, len(self._states) - 1)])


def _diag_ready():
    """首帧已渲染的诊断：flutter-view 出现 + 语义树有内容。"""
    return {
        "flutter_view_exists": True,
        "glass_pane_exists": True,
        "canvas_count": 1,
        "canvas_kit_loaded": True,
        "semantics_children": 5,
        "js_errors": [],
        "ready_state": "complete",
        "current_url": "http://test-env:8080/?enable_semantics=true",
    }


def _diag_not_rendered():
    """页面打开但未渲染出首帧（无 WASM 错误，纯等待）。"""
    d = _diag_ready()
    d["flutter_view_exists"] = False
    d["canvas_count"] = 0
    d["semantics_children"] = 0
    return d


def _diag_wasm_failed():
    """CanvasKit WASM 下载中断（无 flutter-view + WASM 错误）。"""
    d = _diag_not_rendered()
    d["canvas_kit_loaded"] = False
    d["js_errors"] = [{
        "message": WASM_ABORT,
        "type": "unhandledrejection",
        "stack": "",
    }]
    return d


def _fake_wait(sequence):
    """生成 _wait_first_frame 的替身：依次返回 sequence 中的结果，
    耗尽后保持最后一个值（模拟"持续失败"场景）。

    非 None 值表示"耗时 val 秒后首帧完成"——返回真实单调钟的
    time.monotonic() + val（替身必须返回真实时钟值，固定大数值
    会让耗时差为负）。
    """
    import time

    seq = list(sequence)
    i = 0

    def _fake_wait_first_frame(driver, timeout=180):
        nonlocal i
        val = seq[min(i, len(seq) - 1)]
        i += 1
        if val is None:
            return None
        return time.monotonic() + val

    return _fake_wait_first_frame


class TestMeasureFirstFrame:
    def test_success_first_attempt(self, monkeypatch):
        """正常加载：首帧一次渲染成功，无重试，URL 自动追加语义树参数。"""
        monkeypatch.setattr(
            conftest, "_wait_first_frame", _fake_wait([1000.0])
        )
        driver = _FakeDriver([_diag_ready()])
        result = measure_first_frame_load_time(
            driver, "http://test-env:8080"
        )
        assert result["rendered"] is True
        assert result["first_frame_seconds"] > 0
        assert result["retries"] == 0
        assert driver.get_count == 1
        assert driver.refresh_count == 0
        assert driver.last_url == "http://test-env:8080?enable_semantics=true"

    def test_retry_after_wasm_failure(self, monkeypatch):
        """WASM 加载失败 1 次后刷新恢复：重试 1 次，耗时按最后导航计时。"""
        monkeypatch.setattr(
            conftest, "_wait_first_frame", _fake_wait([None, 2000.0])
        )
        driver = _FakeDriver([_diag_wasm_failed(), _diag_ready()])
        result = measure_first_frame_load_time(
            driver, "http://test-env:8080"
        )
        assert result["rendered"] is True
        assert result["retries"] == 1
        assert driver.refresh_count == 1
        assert driver.get_count == 1  # 刷新不重新 get，计时在循环内重置

    def test_exhaust_retries_on_persistent_wasm_failure(self, monkeypatch):
        """WASM 持续失败：最多重试 max_retries 次后放弃，标记渲染失败。"""
        monkeypatch.setattr(
            conftest, "_wait_first_frame", _fake_wait([None])
        )
        driver = _FakeDriver([_diag_wasm_failed()])
        result = measure_first_frame_load_time(
            driver, "http://test-env:8080"
        )
        assert result["rendered"] is False
        assert result["first_frame_seconds"] is None
        assert result["retries"] == 3
        assert driver.refresh_count == 3

    def test_custom_max_retries(self, monkeypatch):
        """max_retries 可配置：持续失败时按配置上限重试。"""
        monkeypatch.setattr(
            conftest, "_wait_first_frame", _fake_wait([None])
        )
        driver = _FakeDriver([_diag_wasm_failed()])
        result = measure_first_frame_load_time(
            driver, "http://test-env:8080", max_retries=5
        )
        assert result["rendered"] is False
        assert result["retries"] == 5
        assert driver.refresh_count == 5

    def test_no_retry_when_not_wasm_failure(self, monkeypatch):
        """非 WASM 失败（页面异常/超时）不刷新重试，直接失败。"""
        monkeypatch.setattr(
            conftest, "_wait_first_frame", _fake_wait([None])
        )
        driver = _FakeDriver([_diag_not_rendered()])
        result = measure_first_frame_load_time(
            driver, "http://test-env:8080"
        )
        assert result["rendered"] is False
        assert result["first_frame_seconds"] is None
        assert result["retries"] == 0
        assert driver.refresh_count == 0

    def test_refresh_error_stops_retrying(self, monkeypatch):
        """刷新异常（页面导航中）时终止重试，不无限循环。"""
        monkeypatch.setattr(
            conftest, "_wait_first_frame", _fake_wait([None, None, None, None])
        )
        driver = _FakeDriver([_diag_wasm_failed()])
        driver.refresh_errors = True
        result = measure_first_frame_load_time(
            driver, "http://test-env:8080"
        )
        assert result["rendered"] is False
        assert result["retries"] == 0
        assert driver.refresh_count == 0

    def test_url_with_existing_semantics_param(self, monkeypatch):
        """URL 已带 enable_semantics=true 时不重复追加。"""
        monkeypatch.setattr(
            conftest, "_wait_first_frame", _fake_wait([1000.0])
        )
        driver = _FakeDriver([_diag_ready()])
        measure_first_frame_load_time(
            driver, "http://test-env:8080/?foo=1&enable_semantics=true"
        )
        assert driver.last_url == (
            "http://test-env:8080/?foo=1&enable_semantics=true"
        )
