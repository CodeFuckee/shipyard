"""
测试 frontend/ci/bump_version.py — 版本号自动 +1 脚本。

CI 中 frontend:build_web 阶段调用该脚本：
- 将 pubspec.yaml 的 version: X.Y.Z+N 递增为 X.Y.(Z+1).(N+1)（patch 版本 +1 且 build number +1）
- stdout 输出新版本号
- --output 可把新版本号写入指定文件（CI 用它生成 version_info.txt artifact）
- 版本行缺失 / 格式非法时必须以非零退出码失败（不能静默使用旧版本）
"""

import re
import subprocess
import sys
from pathlib import Path

import pytest

BACKEND_ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = BACKEND_ROOT.parent
SCRIPT = PROJECT_ROOT / "frontend" / "ci" / "bump_version.py"


@pytest.fixture(scope="module")
def script_path():
    if not SCRIPT.exists():
        pytest.fail(f"bump_version.py 不存在: {SCRIPT}（功能未实现）")
    return SCRIPT


def _run(script, pubspec_path, *extra_args):
    """运行脚本，返回 (exit_code, stdout, stderr)。"""
    proc = subprocess.run(
        [sys.executable, str(script), "--pubspec", str(pubspec_path), *extra_args],
        capture_output=True,
        text=True,
    )
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


def _write_pubspec(path: Path, version_line: str, extra="description: test"):
    """写一个最小 pubspec.yaml（可带 version 行或留空模拟缺失）。"""
    content = f"name: test\n{extra}\n"
    if version_line:
        content += f"version: {version_line}\n"
    content += "environment:\n  sdk: ^3.0.0\n"
    path.write_text(content, encoding="utf-8")


class TestBumpVersionNormal:
    """正常路径：版本号递增。"""

    def test_bump_patch_and_build_number(self, script_path, tmp_path):
        """1.0.2+3 → 1.0.3+4：patch 版本 +1 且 build number +1。"""
        pubspec = tmp_path / "pubspec.yaml"
        _write_pubspec(pubspec, "1.0.2+3")

        code, out, err = _run(script_path, pubspec)

        assert code == 0, f"退出码应为 0，实际 {code}，stderr: {err}"
        assert out == "1.0.3+4"
        content = pubspec.read_text(encoding="utf-8")
        assert re.search(r"^version: 1\.0\.3\+4$", content, re.M), (
            f"pubspec.yaml 应写回 version: 1.0.3+4，实际内容:\n{content}"
        )

    def test_bump_without_build_number(self, script_path, tmp_path):
        """1.0.2（无 +N）→ 1.0.3+1：无 build number 时补 1。"""
        pubspec = tmp_path / "pubspec.yaml"
        _write_pubspec(pubspec, "1.0.2")

        code, out, err = _run(script_path, pubspec)

        assert code == 0, f"退出码应为 0，实际 {code}，stderr: {err}"
        assert out == "1.0.3+1"
        assert re.search(r"^version: 1\.0\.3\+1$", pubspec.read_text(encoding="utf-8"), re.M)

    def test_bump_carry_patch_to_10(self, script_path, tmp_path):
        """1.0.9+5 → 1.0.10+6：patch 位进位到两位数。"""
        pubspec = tmp_path / "pubspec.yaml"
        _write_pubspec(pubspec, "1.0.9+5")

        code, out, err = _run(script_path, pubspec)

        assert code == 0, f"退出码应为 0，实际 {code}，stderr: {err}"
        assert out == "1.0.10+6"

    def test_bump_max_values(self, script_path, tmp_path):
        """9.9.9+9 → 9.9.10+10：大数边界。"""
        pubspec = tmp_path / "pubspec.yaml"
        _write_pubspec(pubspec, "9.9.9+9")

        code, out, err = _run(script_path, pubspec)

        assert code == 0, f"退出码应为 0，实际 {code}，stderr: {err}"
        assert out == "9.9.10+10"

    def test_bump_zero_patch(self, script_path, tmp_path):
        """1.2.0+1 → 1.2.1+2：patch 为 0 时正常 +1。"""
        pubspec = tmp_path / "pubspec.yaml"
        _write_pubspec(pubspec, "1.2.0+1")

        code, out, err = _run(script_path, pubspec)

        assert code == 0, f"退出码应为 0，实际 {code}，stderr: {err}"
        assert out == "1.2.1+2"


class TestBumpVersionOutput:
    """--output 参数：把新版本号写入指定文件（CI 生成 version_info.txt 用）。"""

    def test_output_file_contains_new_version(self, script_path, tmp_path):
        pubspec = tmp_path / "pubspec.yaml"
        output = tmp_path / "version_info.txt"
        _write_pubspec(pubspec, "1.0.2+3")

        code, out, err = _run(script_path, pubspec, "--output", str(output))

        assert code == 0, f"退出码应为 0，实际 {code}，stderr: {err}"
        assert output.read_text(encoding="utf-8").strip() == "1.0.3+4"

    def test_output_file_directory_not_exist_fails(self, script_path, tmp_path):
        """输出目录不存在时必须失败，不能静默跳过。"""
        pubspec = tmp_path / "pubspec.yaml"
        _write_pubspec(pubspec, "1.0.2+3")
        bad_output = tmp_path / "no_such_dir" / "version_info.txt"

        code, out, err = _run(script_path, pubspec, "--output", str(bad_output))

        assert code != 0, "输出目录不存在时脚本必须失败"


class TestBumpVersionErrors:
    """异常输入：必须非零退出，不能静默使用旧版本。"""

    def test_missing_version_line_fails(self, script_path, tmp_path):
        pubspec = tmp_path / "pubspec.yaml"
        _write_pubspec(pubspec, None)

        code, out, err = _run(script_path, pubspec)

        assert code != 0, "version 行缺失时脚本必须失败"
        assert "version" in err.lower(), f"stderr 应说明版本行问题，实际: {err}"

    def test_invalid_version_format_fails(self, script_path, tmp_path):
        pubspec = tmp_path / "pubspec.yaml"
        _write_pubspec(pubspec, "abc")

        code, out, err = _run(script_path, pubspec)

        assert code != 0, "version 格式非法时脚本必须失败"

    def test_missing_pubspec_file_fails(self, script_path, tmp_path):
        missing = tmp_path / "pubspec.yaml"

        code, out, err = _run(script_path, missing)

        assert code != 0, "pubspec.yaml 不存在时脚本必须失败"

    def test_version_line_untouched_on_error(self, script_path, tmp_path):
        """校验失败时不得修改 pubspec.yaml 内容。"""
        pubspec = tmp_path / "pubspec.yaml"
        original = "name: test\ndescription: test\nversion: abc\n"
        pubspec.write_text(original, encoding="utf-8")

        code, out, err = _run(script_path, pubspec)

        assert code != 0
        assert pubspec.read_text(encoding="utf-8") == original, (
            "校验失败时不应修改 pubspec.yaml"
        )


class TestBumpVersionIdempotence:
    """重复调用：连续运行两次必须连续递增（CI 重跑时基于远程 HEAD 再 +1）。"""

    def test_double_run_increments_twice(self, script_path, tmp_path):
        pubspec = tmp_path / "pubspec.yaml"
        _write_pubspec(pubspec, "1.0.2+3")

        code1, out1, _ = _run(script_path, pubspec)
        code2, out2, _ = _run(script_path, pubspec)

        assert (code1, code2) == (0, 0)
        assert out1 == "1.0.3+4"
        assert out2 == "1.0.4+5"
