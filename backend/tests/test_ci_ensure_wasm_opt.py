"""复现 frontend:build_web 在 macOS runner 上失败的 CI 脚本 bug。

背景（流水线 689 失败，job frontend:build_web）：
- build_web 的 wasm-opt 安装逻辑只支持 Linux amd64（下载 Debian sid 的
  binaryen_120-4_amd64.deb），且脚本没有 set -e —— 下载/解包/cp 失败时
  不会中止，还会假打印 "✓ wasm-opt 已安装"，最终 exit 0。
- 该 job 在两个带 flutter/harmony 标签的 runner（nas=linux amd64、
  Mac mini=darwin arm64）间随机调度；落到 macOS 上时安装必然失败，
  但 job 不报错，直到 dart2wasm 调用缺失的 wasm-opt 才抛
  ProcessException: No such file or directory，构建失败。

本测试通过 WASM_OPT_UTILS_DIR / WASM_OPT_INSTALL_CMD 注入，把安装逻辑
当成独立单元验证，断言"安装失败必须让 job 失败（非 0 退出）"。
"""
import os
import stat
import subprocess
from pathlib import Path

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "frontend" / "ci" / "ensure_wasm_opt.sh"

MOCK_WASM_OPT = """#!/usr/bin/env bash
if [ "$1" = "--version" ]; then
  echo "wasm-opt 120 (mock)"
  exit 0
fi
exit 0
"""


def make_fake_wasm_opt(utils_dir: Path) -> Path:
    """在 utils 目录里放一个假的 wasm-opt 可执行文件。"""
    utils_dir.mkdir(parents=True, exist_ok=True)
    p = utils_dir / "wasm-opt"
    p.write_text(MOCK_WASM_OPT)
    p.chmod(p.stat().st_mode | stat.S_IEXEC)
    return p


def run_script(tmp_path, install_cmd=None, platform=None):
    """以隔离环境运行 ensure_wasm_opt.sh，返回 CompletedProcess。"""
    env = os.environ.copy()
    env["WASM_OPT_UTILS_DIR"] = str(tmp_path / "utils")
    if install_cmd is not None:
        env["WASM_OPT_INSTALL_CMD"] = install_cmd
    if platform is not None:
        env["WASM_OPT_UNAME_S"] = platform
    return subprocess.run(
        ["bash", str(SCRIPT)],
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )


@pytest.mark.xfail(
    strict=True,
    reason="方案 B（用户选择）仅锁定 Linux runner，脚本假成功隐患未修（Linux 上 deb 安装恰好可用）；若脚本改为安装失败即报错（方案 A），此测试应恢复为通过",
)
def test_install_failure_must_exit_nonzero(tmp_path):
    """核心复现：wasm-opt 缺失且安装失败时，脚本必须非 0 退出。

    旧行为：安装命令失败被忽略（无 set -e），wasm-opt 未生成仍打印
    "✓ 已安装" 并以 0 退出，导致 dart2wasm 阶段才报错 —— 正是
    流水线 689 在 macOS runner 上失败的根因。
    """
    result = run_script(tmp_path, install_cmd="exit 1")

    assert result.returncode != 0, (
        f"安装失败时脚本必须报错退出（旧代码假成功 exit 0）。stdout={result.stdout!r}"
    )
    assert "wasm-opt" in (result.stdout + result.stderr)


def test_wasm_opt_present_skips_install(tmp_path):
    """已存在可用的 wasm-opt 时跳过安装（幂等），且不执行安装命令。"""
    utils_dir = tmp_path / "utils"
    make_fake_wasm_opt(utils_dir)
    marker = tmp_path / "marker"

    result = run_script(tmp_path, install_cmd=f"touch {marker}")

    assert result.returncode == 0
    assert not marker.exists(), "已存在 wasm-opt 时不应执行安装命令"
    assert "跳过安装" in result.stdout


def test_install_success_ok(tmp_path):
    """安装命令成功生成 wasm-opt 后，脚本正常退出 0。"""
    utils_dir = tmp_path / "utils"
    install_cmd = (
        f"mkdir -p {utils_dir} && "
        f"cat > {utils_dir}/wasm-opt <<'EOF'\n{MOCK_WASM_OPT}EOF\n"
        f"chmod +x {utils_dir}/wasm-opt"
    )

    result = run_script(tmp_path, install_cmd=install_cmd)

    assert result.returncode == 0, f"stdout={result.stdout!r} stderr={result.stderr!r}"
    assert (utils_dir / "wasm-opt").exists()
    assert "已安装" in result.stdout


def test_build_web_tags_pin_linux_runner():
    """方案 B（调度侧修复）：frontend:build_web 的 tags 必须包含 linux。

    两个 flutter/harmony 标签的 runner（nas=linux amd64、Mac=darwin arm64）
    随机调度，job 落到 macOS 上 wasm-opt 安装逻辑必然失败（流水线 689）。
    只有 nas 同时具备 flutter+harmony+linux 标签，加上 linux 后 job 只会
    被 Linux runner 领取。
    """
    ci = yaml.safe_load((REPO_ROOT / ".gitlab-ci.yml").read_text(encoding="utf-8"))
    job = ci["frontend:build_web"]
    tags = job.get("tags", [])
    assert "linux" in tags, f"build_web tags={tags} 必须包含 linux（仅 nas Linux runner 匹配）"


def test_build_web_exports_ld_library_path_after_ensure_wasm_opt():
    """build_web 必须在 ensure_wasm_opt.sh 之后于父 shell export LD_LIBRARY_PATH。

    回归点（流水线 #690）：wasm-opt 安装逻辑提取到脚本后，export 只发生在
    `bash ci/ensure_wasm_opt.sh` 子进程内，父 shell 的 flutter build 拿不到
    LD_LIBRARY_PATH，dart2wasm 启动 wasm-opt 时报
    "libbinaryen.so: cannot open shared object file"。
    """
    ci = yaml.safe_load((REPO_ROOT / ".gitlab-ci.yml").read_text(encoding="utf-8"))
    script_text = "\n".join(ci["frontend:build_web"]["script"])

    assert "ensure_wasm_opt" in script_text, "build_web 必须调用 ci/ensure_wasm_opt.sh"
    assert (
        "export LD_LIBRARY_PATH" in script_text
    ), "build_web 必须在父 shell export LD_LIBRARY_PATH（wasm-opt 依赖 libbinaryen.so）"
    idx_ensure = script_text.index("ensure_wasm_opt")
    idx_export = script_text.index("export LD_LIBRARY_PATH")
    assert (
        idx_export > idx_ensure
    ), "export LD_LIBRARY_PATH 必须位于 ensure_wasm_opt.sh 调用之后，否则子进程内 export 不生效"
