"""首帧加载速度计时测试 — 测量 Flutter Web 首帧渲染耗时。

测量方法：
- 通过 CDP `Page.addScriptToEvaluateOnNewDocument` 在页面加载前注入计时脚本；
- 以浏览器 `performance.now()` 为基准，记录导航开始后
  `flt-glass-pane`（Flutter 渲染层出现）与 `flutter-view`（应用挂载）的时间点；
- 每个用例连续导航 N 次取中位数，减少缓存/调度抖动影响。

说明：
- 首帧测量受浏览器缓存状态影响显著（首次冷加载需下载 CanvasKit），
  本测试用"热缓存"状态对比（第 2+ 次导航），优化前后控制变量一致。
- 仅支持 Chrome（依赖 CDP），Firefox 下自动跳过。
- 不写硬性阈值断言：首帧耗时受 CI 机器性能/网络影响大，
  结果通过 -s 输出，供人工与 CI 报告对比。
"""

import os
import statistics
import sys
import time

import pytest

# 确保 selenium_tests 目录在 sys.path 中，以便导入 conftest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import BASE_URL, BROWSER  # noqa: E402
from conftest import (  # noqa: E402
    _create_chrome_driver,
    _is_server_reachable,
    _try_http,
)

MEASURE_SCRIPT = r"""
(function() {
  if (window.__ffMarks) return;
  window.__ffMarks = { navStart: performance.now() };
  var poll = function() {
    var t = performance.now();
    if (window.__ffMarks.glassPane === undefined &&
        document.querySelector('flt-glass-pane')) {
      window.__ffMarks.glassPane = t;
    }
    if (window.__ffMarks.flutterView === undefined &&
        document.querySelector('flutter-view')) {
      window.__ffMarks.flutterView = t;
    }
    if (window.__ffMarks.glassPane !== undefined &&
        window.__ffMarks.flutterView !== undefined) {
      return; // 两个标记都出现，停止轮询
    }
    setTimeout(poll, 20);
  };
  poll();
})();
"""


@pytest.mark.skipif(BROWSER != "chrome", reason="首帧计时依赖 CDP，仅支持 Chrome")
def test_first_frame_timing():
    """测量 Flutter 首帧耗时（glass-pane 出现 / flutter-view 挂载）。"""
    if not (_is_server_reachable(BASE_URL) and _try_http(BASE_URL)):
        pytest.skip(f"服务器不可达: {BASE_URL}")

    driver = _create_chrome_driver()
    try:
        # 注入计时脚本（每次导航前执行）
        driver.execute_cdp_cmd(
            "Page.addScriptToEvaluateOnNewDocument",
            {"source": MEASURE_SCRIPT},
        )

        # 预热阶段：第 1 次导航下载 CanvasKit 等资源，且 chromedriver/Chrome
        # 进程首次启动存在预热效应，统一丢弃前 3 次，只统计稳定后的样本。
        total_runs = 10
        warmup_runs = 3
        for i in range(warmup_runs):
            driver.get(BASE_URL)
            _wait_marks(driver)

        glass_pane_times = []
        flutter_view_times = []
        for i in range(warmup_runs, total_runs):
            driver.get(BASE_URL)
            marks = _wait_marks(driver)
            glass = marks["glassPane"] - marks["navStart"]
            view = marks["flutterView"] - marks["navStart"]
            glass_pane_times.append(glass)
            flutter_view_times.append(view)
            print(f"\n  [run {i + 1}/{total_runs}] glass-pane: {glass:.0f}ms | "
                  f"flutter-view: {view:.0f}ms")

        print("\n  ---- 首帧耗时汇总 (热缓存, 丢弃前"
              f"{warmup_runs} 次预热) ----")
        print(f"  glass-pane  (中位数): {statistics.median(glass_pane_times):.0f}ms"
              f"   (各次: {[f'{t:.0f}' for t in glass_pane_times]})")
        print(f"  flutter-view(中位数): {statistics.median(flutter_view_times):.0f}ms"
              f"   (各次: {[f'{t:.0f}' for t in flutter_view_times]})")

        # 宽松防挂断言：首帧应在 60 秒内完成
        assert max(glass_pane_times + flutter_view_times) < 60_000, \
            "首帧耗时超过 60 秒，疑似渲染失败"
    finally:
        driver.quit()


def _wait_marks(driver, timeout: int = 60):
    """等待注入脚本的两个标记都出现，返回标记字典。"""
    deadline = time.time() + timeout
    marks = {}
    while time.time() < deadline:
        marks = driver.execute_script("return window.__ffMarks || null;")
        if marks and marks.get("glassPane") is not None and marks.get("flutterView") is not None:
            return marks
        time.sleep(0.1)
    raise TimeoutError(
        f"等待 Flutter 首帧标记超时（{timeout}s）。当前标记: {marks}。"
        "请检查页面是否成功加载 Flutter 应用。"
    )
