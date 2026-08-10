"""生产环境首帧加载速度测试（只读，无写操作）。

测量每个生产环境从发起导航到首帧渲染完成（flutter-view 出现且
语义树有内容）的耗时，并将加载时间输出到最终测试结果：
- report.html：通过 pytest-html extra 注入每环境首帧时间（CI artifacts）
- pytest_output.log：print 汇总输出（run_tests.sh 默认加 -s 后可见）

加载时间不设硬性毫秒阈值（不同环境网络/硬件差异大，阈值只会造成
误报），以"首帧是否在超时内渲染完成"为断言；加载时间作为性能
监控数据持续记录，便于观察生产环境性能趋势。
"""

import pytest
import pytest_html

from conftest import measure_first_frame_load_time

pytestmark = pytest.mark.prod_smoke


def _seconds_str(result: dict) -> str:
    """首帧耗时字符串（渲染失败时为 N/A）。"""
    seconds = result.get("first_frame_seconds")
    return f"{seconds:.1f}s" if seconds is not None else "N/A"


def _retry_note(result: dict) -> str:
    """WASM 重试次数的备注（未重试时为空串）。"""
    retries = result.get("retries", 0)
    return f"，WASM 重试 {retries} 次" if retries else ""


def _result_to_html(result: dict) -> str:
    """首帧测量结果转 HTML 片段（注入 pytest-html 报告）。"""
    rendered = result["rendered"]
    color = "#28a745" if rendered else "#dc3545"
    status = "渲染成功" if rendered else "渲染失败"
    return (
        f'<div style="margin:4px 0">'
        f'<span style="font-weight:600">首帧加载时间</span>'
        f'（{result["url"]}）: '
        f'<span style="color:{color};font-weight:600">'
        f'{_seconds_str(result)}</span>'
        f'（{status}{_retry_note(result)}）</div>'
    )


class TestProdFirstFrame:
    """生产环境首帧加载速度（每环境参数化，结果输出到最终测试报告）。"""

    def test_first_frame_load_time(self, first_frame_driver, prod_url, extras):
        """测量首帧加载时间并输出到最终测试结果。

        断言：首帧必须在超时内渲染完成（flutter-view + 语义树有内容），
        且测量到的耗时为正值。加载时间通过 pytest-html extras 写入
        report.html，通过 print 进入 pytest_output.log。
        """
        result = measure_first_frame_load_time(first_frame_driver, prod_url)

        # 输出到最终测试结果（report.html + pytest_output.log）
        print(
            f"[首帧] {result['url']}: {_seconds_str(result)}"
            f"（{'渲染成功' if result['rendered'] else '渲染失败'}"
            f"{_retry_note(result)}）"
        )
        extras.append(pytest_html.extras.html(_result_to_html(result)))

        # 断言首帧渲染成功（首帧时间由轮询超时保证上限，此处仅做有效值检查）
        assert result["rendered"], (
            f"首帧渲染失败（{prod_url}）: {result['diag']}"
        )
        assert result["first_frame_seconds"] > 0, (
            f"首帧耗时异常（{prod_url}）: {result}"
        )
