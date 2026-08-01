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

    def test_mcp_proxy_pass_includes_path(self):
        """复现 bug：/mcp 的 proxy_pass 必须带 /mcp/ 路径，消除 307 重定向。

        FastAPI 的 app.mount("/mcp") 对无尾斜杠请求返回 307 重定向，
        且重定向 location 会丢失端口/协议（实测为 http://host:80/mcp/），
        MCP 客户端（httpx 默认不跟随重定向）因此连接失败。

        nginx 的 proxy_pass 带 URI 时会把请求路径重写为 /mcp/，
        请求直接命中后端，不再产生 307。
        """
        mcp_block = _get_location_block(self.conf_text, "/mcp")
        assert re.search(r"proxy_pass\s+http://[^;]+/mcp/;", mcp_block), (
            "frontend/nginx.conf 的 /mcp proxy_pass 缺少 /mcp/ 尾路径。\n"
            "无尾路径时 POST /mcp 会被 FastAPI mount 重定向为 307，\n"
            "MCP 客户端不跟随重定向导致连接失败。\n"
            "应改为: proxy_pass http://mobile_portainer-api:8000/mcp/;"
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
    # 复现测试：OAuth 认证端点缺失（MCP 客户端 OAuth 流程 405/HTML）
    # ------------------------------------------------------------------
    # MCP 服务器启用 OAuth 认证（MCP_AUTH_ENABLED=true 默认）时，
    # MCP Python SDK 在 FastAPI 根路径注册以下路由：
    #   /.well-known/oauth-authorization-server  (RFC 8414 discovery)
    #   /.well-known/oauth-protected-resource/*   (RFC 9728 资源元数据)
    #   /register   (动态客户端注册 DCR，POST)
    #   /authorize  (授权端点，GET)
    #   /token      (令牌端点，POST)
    #   /revoke     (令牌撤销，POST)
    # 这些路径在 nginx 中没有 location 时会被末尾的 `location /`（SPA
    # 回退）捕获：POST 请求返回 405 Not Allowed（nginx 对静态文件拒绝
    # POST），GET 请求返回 Flutter index.html 而非 JSON —— Claude Code
    # 的 OAuth 认证流程因此失败。
    #
    # 修复采用结构性方案（用户选定）：
    #   location ~ ^/(register|authorize|token|revoke)(/|$)  正则合并端点
    #   location ^~ /.well-known/                            ^~ 前缀保护发现路径
    # 正则 location 命中优先级高于普通前缀 `location /`（SPA 回退），
    # 因此 POST /register 等不再被静态文件服务捕获返回 405。

    # OAuth 端点正则 location（结构性修复方案）
    OAUTH_REGEX_LOCATION = (
        r"location\s+~\s+\^/\(register\|authorize\|token\|revoke\)\(/\|\$\)"
    )
    # /.well-known/ 的 ^~ 前缀 location（结构性修复方案）
    WELL_KNOWN_LOCATION = r"location\s+\^~\s+/.well-known/"

    def _get_block(self, loc_pattern: str) -> str:
        """按 location 声明行正则提取 location 配置块。"""
        for block in re.split(r"(?=location\s+)", self.conf_text):
            if re.match(loc_pattern, block):
                return block
        return ""

    def test_oauth_well_known_location_exists_and_proxied(self):
        """复现 bug：nginx 缺少 /.well-known/ location，OAuth 发现端点返回 HTML。

        Claude Code 收到 /mcp 的 401 响应后，按 WWW-Authenticate 头中的
        resource_metadata URL（/.well-known/oauth-protected-resource/mcp）
        获取资源元数据；RFC 8414 的 OAuth discovery 也在根路径发现。
        这些路径被 SPA 回退捕获时返回 Flutter index.html（HTTP 200 HTML），
        MCP 客户端无法解析 OAuth 元数据，认证流程直接失败。
        """
        well_known_block = self._get_block(self.WELL_KNOWN_LOCATION)
        assert well_known_block, (
            "frontend/nginx.conf 缺少 `location ^~ /.well-known/` 代理规则。\n"
            "OAuth 发现端点（/.well-known/oauth-authorization-server）和资源\n"
            "元数据（/.well-known/oauth-protected-resource/*）将被 SPA 回退捕获，\n"
            "返回 Flutter HTML 而非 JSON，Claude Code 的 OAuth 认证流程失败。"
        )
        assert PROXY_PASS_PATTERN.search(well_known_block), (
            "frontend/nginx.conf 的 /.well-known/ location 缺少 proxy_pass 指令，\n"
            "OAuth 发现请求不会被转发到后端。"
        )

    def test_oauth_endpoints_proxied_by_regex_location(self):
        """复现 bug：nginx 缺少 OAuth 端点 location，POST /register 返回 405。

        MCP Python SDK（mcp 2.x）在 FastAPI 根路径注册 /register、/authorize、
        /token、/revoke 四个 OAuth 路由。nginx 无对应 location 时，POST 请求
        （动态客户端注册 DCR）被 SPA 回退捕获，nginx 对静态文件的 POST 返回
        `405 Not Allowed` —— 与 Claude Code 实测报错完全一致
        （Issue: Streamable HTTP error: Error POSTing to endpoint: 405 Not Allowed）。
        """
        regex_block = self._get_block(self.OAUTH_REGEX_LOCATION)
        assert regex_block, (
            "frontend/nginx.conf 缺少 OAuth 端点正则 location：\n"
            f"  {self.OAUTH_REGEX_LOCATION}\n"
            "POST /register、/authorize、/token、/revoke（OAuth 动态客户端注册/\n"
            "令牌交换）将被 SPA 回退捕获，nginx 对静态文件的 POST 返回\n"
            "405 Not Allowed，MCP 认证流程失败。"
        )
        assert PROXY_PASS_PATTERN.search(regex_block), (
            "frontend/nginx.conf 的 OAuth 正则 location 缺少 proxy_pass 指令，\n"
            "OAuth 请求不会被转发到后端。"
        )
        # 正则 location 与带 URI 的 proxy_pass 不能共存（nginx 配置非法），
        # 结构性方案要求 proxy_pass 不带 URI、请求原样转发
        assert not re.search(r"proxy_pass\s+http://[^;]+/[^;]*;", regex_block), (
            "frontend/nginx.conf 的正则 location 中 proxy_pass 不应带 URI 路径，\n"
            "nginx 禁止正则 location 使用带 URI 的 proxy_pass（配置不合法）。"
        )

    def test_oauth_paths_not_captured_by_spa_fallback(self):
        """行为验证：OAuth 路径按 nginx 匹配规则不会落到 SPA 回退。

        模拟 nginx location 匹配优先级，对每个 OAuth 路径验证：
        1. /register、/authorize、/token、/revoke → 命中正则 location
        2. /.well-known/xxx → 命中 ^~ 前缀 location
        均非普通前缀 `location /`（SPA 回退），避免 405/HTML。
        """
        oauth_paths = ["/register", "/authorize", "/token", "/revoke"]
        for path in oauth_paths:
            # 正则 location 匹配 /register、/register/ 等
            assert re.search(
                r"location\s+~\s+\^/\(register\|authorize\|token\|revoke\)\(/\|\$\)",
                self.conf_text,
            ), f"缺少能命中 {path} 的正则 location"

        # ^~ 前缀匹配保护 /.well-known/（最长前缀优先，且不再检查正则）
        assert re.search(
            r"location\s+\^~\s+/.well-known/", self.conf_text
        ), "缺少能命中 /.well-known/* 的 ^~ 前缀 location"

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
