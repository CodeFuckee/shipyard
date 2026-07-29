"""
测试 nginx.web.conf — 验证所有 API 路由路径都已配置反向代理。
复现 bug：/projects 路径在 nginx 配置中缺失，导致请求被 SPA 回退捕获返回 HTML。
"""

import re
from pathlib import Path

import pytest

# 项目根目录
ROOT = Path(__file__).resolve().parent.parent

# nginx 配置文件路径
NGINX_CONF = ROOT / "nginx.web.conf"

# API 后端地址模式
PROXY_PASS_PATTERN = re.compile(r"proxy_pass\s+http://api:8000;")

# 已知在 nginx 中已配置的路径（从主路由+子路由注册的 prefix）
# 实际定义在 main.py 的 app.include_router() 调用中
KNOWN_API_PREFIXES = [
    "/containers",
    "/images",
    "/networks",
    "/volumes",
    "/stacks",
    "/projects",
    "/admin",
    # "/system" 无独立 prefix——system router 在根路径注册了 /info, /self, /git, /usage, /ports
    # nginx 中这些子路径已分别有独立的 location block
    "/ws",
    "/v1.",  # Docker Engine API 代理
    "/mcp",
    "/docs",
    "/redoc",
    "/openapi.json",
]


def _parse_nginx_locations(conf_text: str) -> set[str]:
    """从 nginx 配置中提取所有 location 路径。"""
    locations = set()
    for match in re.finditer(r"location\s+(\S+)", conf_text):
        path = match.group(1)
        locations.add(path)
    return locations


class TestNginxConfig:
    """验证 nginx.web.conf 包含所有 API 路由的代理规则。"""

    @pytest.fixture(autouse=True)
    def _load_config(self):
        """加载 nginx 配置文件。"""
        if not NGINX_CONF.exists():
            pytest.skip(f"nginx 配置文件不存在: {NGINX_CONF}")
        self.conf_text = NGINX_CONF.read_text(encoding="utf-8")
        self.locations = _parse_nginx_locations(self.conf_text)

    # ------------------------------------------------------------------
    # 复现测试：/projects 缺失
    # ------------------------------------------------------------------

    def test_projects_location_exists(self):
        """复现 bug：/projects 在 nginx 中没有 location block，导致返回 HTML。"""
        assert "/projects" in self.locations, (
            "nginx.web.conf 缺少 /projects 的 location 代理规则。\n"
            "前端 GET /projects 请求将被末尾的 `location /` catch-all 规则捕获，\n"
            "返回 Flutter SPA 的 index.html 而非 API JSON 响应。"
        )

    # ------------------------------------------------------------------
    # 完整性验证：确保所有 API prefix 都有对应的 nginx location
    # ------------------------------------------------------------------

    @pytest.mark.parametrize("api_path", KNOWN_API_PREFIXES)
    def test_api_path_has_nginx_proxy(self, api_path: str):
        """验证每个 API 路径在 nginx 中都配置了反向代理。"""
        assert api_path in self.locations, (
            f"nginx.web.conf 缺少 `location {api_path}` 代理规则。\n"
            f"请求 {api_path}/* 将被 SPA 回退捕获，返回 HTML 而非 JSON。"
        )

    # ------------------------------------------------------------------
    # 健康检查：确保已配置的 location 都有 proxy_pass
    # ------------------------------------------------------------------

    def test_all_api_locations_have_proxy_pass(self):
        """验证所有 API location 都正确代理到后端而非服务静态文件。"""
        # 静态文件 location（不应有 proxy_pass）
        static_locations = {"/assets/", "/icons/", "/canvaskit/"}

        # 提取所有 location 块及其内容
        # 简单策略：分割 location 块，检查 API 路径的块是否含 proxy_pass
        blocks = re.split(r"(?=location\s+\S+\s*\{)", self.conf_text)
        missing_proxy: list[str] = []

        for block in blocks:
            loc_match = re.match(r"location\s+(\S+)", block)
            if not loc_match:
                continue
            loc_path = loc_match.group(1)
            # 跳过根路径（SPA 回退）和静态资源路径
            if loc_path == "/" or loc_path in static_locations:
                continue
            if not PROXY_PASS_PATTERN.search(block):
                missing_proxy.append(loc_path)

        assert missing_proxy == [], (
            f"以下 nginx location 缺少 proxy_pass 指令: {missing_proxy}"
        )
