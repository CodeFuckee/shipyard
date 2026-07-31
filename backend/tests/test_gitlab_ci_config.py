"""
测试 .gitlab-ci.yml — 验证 CI 部署脚本中端口映射正确，shell 语法合法。

复现 bug 1：deploy_to_synology job 中 docker run -p 写死映射到容器
8000 端口（FastAPI/uvicorn），绕过 nginx，导致前端页面返回 404。

复现 bug 2：shell 多行续行符 \\ 中间插入 # 注释，破坏续行链，
导致 docker run 参数丢失。
"""

import re
from pathlib import Path

import pytest
import yaml

# 项目根目录
BACKEND_ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = BACKEND_ROOT.parent
CI_FILE = PROJECT_ROOT / ".gitlab-ci.yml"


class TestGitlabCIPortMapping:
    """验证 .gitlab-ci.yml 中的 docker run -p 端口映射指向 nginx (80)。"""

    # ------------------------------------------------------------------
    # 复现测试：deploy job docker run 映射到 8000 而不是 80
    # ------------------------------------------------------------------

    def test_deploy_docker_run_maps_to_nginx_port_80(self):
        """复现 bug：deploy_to_synology 中 docker run -p 映射到 8000 而非 80。

        容器内部架构：
        - nginx (port 80) → 前端静态文件 + API 代理 → uvicorn (127.0.0.1:8000)
        - uvicorn 绑定在 127.0.0.1:8000，不对外暴露

        如果 docker run -p 映射到 8000，请求绕过 nginx 直接打到 FastAPI。
        """
        if not CI_FILE.exists():
            pytest.skip(f"文件不存在: {CI_FILE}")

        content = CI_FILE.read_text(encoding="utf-8")

        # 找到 docker run 命令中的端口映射
        # 匹配: -p ${VAR:-default}:PORT 或 -p host:container
        port_mappings = re.findall(
            r'-p\s+\$\{[^}]+\}:\d+', content
        )
        # 也匹配纯数字的映射（如果存在的话）
        port_mappings += re.findall(
            r'-p\s+\d+:\d+', content
        )

        assert port_mappings, (
            ".gitlab-ci.yml 中未找到 docker run 端口映射。\n"
            "如果部署方式已变更，请更新本测试。"
        )

        # 端口映射必须指向 nginx (80)，不能是 uvicorn (8000)
        bad_mappings = []
        for mapping in port_mappings:
            # 提取容器端口（冒号后的数字）
            match = re.search(r':(\d+)', mapping)
            if match:
                container_port = match.group(1)
                if container_port == "8000":
                    bad_mappings.append(mapping)

        assert bad_mappings == [], (
            f".gitlab-ci.yml 中 docker run -p 端口映射错误！\n"
            f"以下映射指向了容器 8000 端口（FastAPI/uvicorn）：\n"
            f"  {bad_mappings}\n\n"
            f"应改为映射到 80 端口（nginx）。\n"
            f"原因：容器内部 nginx 监听 80 端口，uvicorn 绑定在 127.0.0.1:8000。\n"
            f"映射到 8000 会绕过 nginx，请求直接打到 FastAPI → 404 Not Found。"
        )

    # ------------------------------------------------------------------
    # 完整性验证：确保至少有一个明确的 deploy job 定义了端口映射
    # ------------------------------------------------------------------

    def test_deploy_job_exists_and_has_port_mapping(self):
        """验证 deploy_to_synology job 存在并包含端口映射。"""
        if not CI_FILE.exists():
            pytest.skip(f"文件不存在: {CI_FILE}")

        data = yaml.safe_load(CI_FILE.read_text(encoding="utf-8"))

        deploy_job = data.get("deploy_to_synology")
        assert deploy_job is not None, (
            "找不到 deploy_to_synology job，部署配置可能已变更，请更新本测试。"
        )

        script = deploy_job.get("script", "")
        # script 可能是字符串或列表
        if isinstance(script, list):
            script = "\n".join(script)

        assert "-p " in script, (
            "deploy_to_synology 的 script 中未找到 docker run -p 端口映射。\n"
            "部署方式可能已变更，请更新本测试。"
        )

    # ------------------------------------------------------------------
    # 复现测试：shell 续行符 \\ 中间不能有 # 注释
    # ------------------------------------------------------------------

    def test_no_comment_breaks_shell_line_continuation(self):
        """复现 bug：shell \\ 续行符中间插入 # 注释，导致续行断裂。

        在 shell 中，\\ 会移除换行符并拼接下一行内容。如果拼接后的行
        以 # 开头，则 # 及之后的所有内容（包括后续续行拼接的部分）
        都会被视为注释，导致：
        - docker run 参数被吞掉（包括镜像名）
        - 剩余的续行参数被当作独立命令执行（如 -p: command not found）
        """
        if not CI_FILE.exists():
            pytest.skip(f"文件不存在: {CI_FILE}")

        content = CI_FILE.read_text(encoding="utf-8")
        lines = content.split("\n")

        # 检测模式：一行以 \ 结尾（续行），下一行以 # 开头（注释）
        # 这种模式会破坏 shell 多行命令
        bad_lines = []
        for i, line in enumerate(lines):
            stripped = line.rstrip()
            if stripped.endswith("\\"):
                # 找下一非空行
                next_i = i + 1
                while next_i < len(lines) and lines[next_i].strip() == "":
                    next_i += 1
                if next_i < len(lines):
                    next_line = lines[next_i].lstrip()
                    if next_line.startswith("#"):
                        bad_lines.append(
                            f"  第 {i + 1} 行（以 \\ 结尾）→ "
                            f"第 {next_i + 1} 行（以 # 开头）"
                        )

        assert bad_lines == [], (
            f".gitlab-ci.yml 中 shell 续行符 \\\\ 与 # 注释冲突！\n"
            f"以下位置的 \\\\ 续行紧接着 # 注释，会破坏 shell 多行命令：\n"
            + "\n".join(bad_lines) + "\n\n"
            f"修复方法：将注释移到 docker run 命令之前，或写在 -p 同一行末尾。\n"
            f"不要在 \\\\ 续行链中间插入独立的注释行。"
        )
