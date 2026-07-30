"""
测试 docker-compose 配置 — 验证端口映射正确，确保前端请求经过 nginx。

复现 bug：根目录 docker-compose-cn.yml 将外部端口映射到容器 8000 端口
（FastAPI/uvicorn），绕过了 nginx，导致访问 / 和 /v2 返回 404。
"""

import re
from pathlib import Path

import pytest
import yaml

# 项目根目录（monorepo root）
BACKEND_ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = BACKEND_ROOT.parent

# docker-compose 文件路径
ROOT_COMPOSE_CN = PROJECT_ROOT / "docker-compose-cn.yml"
BACKEND_COMPOSE = BACKEND_ROOT / "docker-compose.yml"
BACKEND_COMPOSE_CN = BACKEND_ROOT / "docker-compose-cn.yml"

# 所有 docker-compose 文件及其预期的容器端口
COMPOSE_FILES = [
    (ROOT_COMPOSE_CN, 80),       # 合并部署：nginx 在容器内监听 80
    (BACKEND_COMPOSE, 80),       # 分离部署 web 服务：nginx 在容器内监听 80
    (BACKEND_COMPOSE_CN, 80),    # 分离部署 web 服务（国内版）：nginx 在容器内监听 80
]


def _parse_ports(compose_data: dict) -> list[tuple[str, str]]:
    """从 docker-compose 数据中提取所有端口映射 (host_port, container_port)。

    注意：host 端口可能包含 bash 变量替换如 ${WEB_PORT:-8080}，其中包含冒号。
    因此从末尾取容器端口（最后一个冒号之后的部分），而非按索引。
    """
    mappings = []
    for service_name, service in compose_data.get("services", {}).items():
        for port_entry in service.get("ports", []):
            # 格式: "host:container" 或 "host:container/protocol"
            # ${WEB_PORT:-8080}:8000 → 容器端口是最后的 8000
            if isinstance(port_entry, str):
                parts = port_entry.rsplit(":", 1)  # 从右边分割，只分一次
                if len(parts) == 2:
                    host_port = parts[0]  # 可能是变量如 "${WEB_PORT:-8080}"
                    container_part = parts[1].split("/")[0]
                    mappings.append((host_port, container_part))
    return mappings


class TestDockerComposePortMapping:
    """验证所有 docker-compose 文件的端口映射正确。"""

    # ------------------------------------------------------------------
    # 复现测试：根目录 docker-compose-cn.yml 端口映射错误
    # ------------------------------------------------------------------

    def test_root_compose_cn_maps_to_nginx_port_80(self):
        """复现 bug：根目录 docker-compose-cn.yml 端口映射到 8000 而非 80。

        容器内部架构：
        - nginx (port 80) → 前端静态文件 + API 代理 → uvicorn (127.0.0.1:8000)
        - uvicorn 绑定在 127.0.0.1:8000，不对外暴露

        如果端口映射到 8000，请求绕过 nginx 直接打到 FastAPI，
        FastAPI 没有 / 和 /v2 路由 → 返回 404。
        """
        if not ROOT_COMPOSE_CN.exists():
            pytest.skip(f"文件不存在: {ROOT_COMPOSE_CN}")

        data = yaml.safe_load(ROOT_COMPOSE_CN.read_text(encoding="utf-8"))
        ports = _parse_ports(data)

        assert ports, "docker-compose-cn.yml 中没有找到 ports 映射"

        for host_port, container_port in ports:
            assert container_port == "80", (
                f"根目录 docker-compose-cn.yml 端口映射错误！\n"
                f"当前映射: {host_port}:{container_port}\n"
                f"期望映射: {host_port}:80\n\n"
                f"原因：容器内部 nginx 监听 80 端口，uvicorn 绑定在 127.0.0.1:8000。\n"
                f"映射到 8000 会绕过 nginx，请求直接打到 FastAPI → 404 Not Found。\n"
                f"这是导致部署后访问 / 和 /v2 报 404 的根因。"
            )

    # ------------------------------------------------------------------
    # 完整性验证：所有 docker-compose 文件的端口映射
    # ------------------------------------------------------------------

    @pytest.mark.parametrize("compose_path,expected_container_port", COMPOSE_FILES)
    def test_compose_maps_to_nginx_port(
        self, compose_path: Path, expected_container_port: int
    ):
        """验证所有 docker-compose 文件中对外暴露的端口映射到 nginx（80）而非 uvicorn（8000）。"""
        if not compose_path.exists():
            pytest.skip(f"文件不存在: {compose_path}")

        data = yaml.safe_load(compose_path.read_text(encoding="utf-8"))
        ports = _parse_ports(data)

        assert ports, f"{compose_path.name} 中没有找到 ports 映射"

        for host_port, container_port in ports:
            assert container_port == str(expected_container_port), (
                f"{compose_path.name} 端口映射错误！\n"
                f"当前: {host_port}:{container_port}\n"
                f"期望: {host_port}:{expected_container_port}"
            )
