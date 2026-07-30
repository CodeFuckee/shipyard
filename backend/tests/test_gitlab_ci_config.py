"""
测试 .gitlab-ci.yml — 验证 CI 部署脚本中端口映射正确。

复现 bug：deploy_to_synology job 中 docker run -p 写死映射到容器
8000 端口（FastAPI/uvicorn），绕过 nginx，导致前端页面返回 404。
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
