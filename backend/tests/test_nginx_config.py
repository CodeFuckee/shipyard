"""
测试 frontend/nginx.conf — 验证所有 API 路由路径都已配置反向代理。

frontend/nginx.conf 是全项目唯一的 nginx 配置源：
- 根目录 Dockerfile.cn（All-in-One 部署镜像）直接 COPY 它
- backend/Dockerfile.web(.cn)（docker-compose 独立 web 容器）COPY 它并
  sed 替换 proxy_pass 目标为 api:8000

复现 bug：/mcp 路径在 frontend/nginx.conf 中缺失，导致 Claude Code CLI
的 POST /mcp 请求被 SPA 回退捕获，nginx 返回 405 Not Allowed。
"""

import re
from pathlib import Path

import pytest

# 项目根目录（backend/tests/ 上两级）
ROOT = Path(__file__).resolve().parent.parent.parent

# 唯一 nginx 配置文件路径（docker-compose 与 All-in-One 镜像共用）
NGINX_CONF = ROOT / "frontend" / "nginx.conf"

# API 后端地址模式（All-in-One 为 mobile_portainer-api:8000，
# docker-compose 构建时 sed 为 api:8000 / 127.0.0.1:8000）
PROXY_PASS_PATTERN = re.compile(r"proxy_pass\s+http://[^;]+;")

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


def _get_location_block(conf_text: str, target: str) -> str:
    """提取指定 location 的配置块，未找到返回空字符串。"""
    for block in re.split(r"(?=location\s+\S+\s*\{)", conf_text):
        loc_match = re.match(r"location\s+(\S+)", block)
        if loc_match and loc_match.group(1) == target:
            return block
    return ""


class TestNginxConfig:
    """验证 frontend/nginx.conf 包含所有 API 路由的代理规则。"""

    @pytest.fixture(autouse=True)
    def _load_config(self):
        """加载 nginx 配置文件。"""
        if not NGINX_CONF.exists():
            pytest.skip(f"nginx 配置文件不存在: {NGINX_CONF}")
        self.conf_text = NGINX_CONF.read_text(encoding="utf-8")
        self.locations = _parse_nginx_locations(self.conf_text)

    # ------------------------------------------------------------------
    # 复现测试：/mcp 缺失（All-in-One 部署 405 Not Allowed）
    # ------------------------------------------------------------------

    def test_mcp_location_exists(self):
        """复现 bug：frontend/nginx.conf 缺少 /mcp 的 location 代理规则。

        缺少该规则时，Claude Code CLI 的 POST /mcp 请求被末尾的
        `location /`（SPA 静态文件回退）捕获，nginx 对静态资源的
        POST 请求返回 405 Not Allowed。
        """
        assert "/mcp" in self.locations, (
            "frontend/nginx.conf 缺少 `location /mcp` 代理规则。\n"
            "POST /mcp 请求将被 SPA 回退捕获，nginx 返回 405 Not Allowed。"
        )

    def test_mcp_location_has_proxy_pass(self):
        """复现 bug：/mcp location 必须代理到后端 API 而非服务静态文件。"""
        mcp_block = _get_location_block(self.conf_text, "/mcp")
        assert PROXY_PASS_PATTERN.search(mcp_block), (
            "frontend/nginx.conf 的 /mcp location 缺少 proxy_pass 指令，\n"
            "请求不会被转发到后端 MCP 端点。"
        )

    def test_mcp_location_has_sse_config(self):
        """复现 bug：/mcp 需要 SSE 长连接配置（Streamable HTTP 传输）。

        Claude Code CLI 通过 Streamable HTTP 与 MCP 通信，响应使用
        SSE 流式传输。缺少 proxy_buffering off 会导致响应被 nginx
        缓冲，长连接会被 proxy_read_timeout（默认 60s）中断。
        """
        mcp_block = _get_location_block(self.conf_text, "/mcp")
        assert "proxy_buffering off;" in mcp_block, (
            "frontend/nginx.conf 的 /mcp location 缺少 `proxy_buffering off;`，\n"
            "SSE 流式响应会被 nginx 缓冲，导致 MCP 通信异常。"
        )
        assert "proxy_read_timeout" in mcp_block, (
            "frontend/nginx.conf 的 /mcp location 缺少长连接超时配置\n"
            "`proxy_read_timeout 86400;`，SSE 长连接默认 60s 会被中断。"
        )

    # ------------------------------------------------------------------
    # 复现测试：/projects 缺失
    # ------------------------------------------------------------------

    def test_projects_location_exists(self):
        """复现 bug：/projects 在 nginx 中没有 location block，导致返回 HTML。"""
        assert "/projects" in self.locations, (
            "frontend/nginx.conf 缺少 /projects 的 location 代理规则。\n"
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
            f"frontend/nginx.conf 缺少 `location {api_path}` 代理规则。\n"
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
