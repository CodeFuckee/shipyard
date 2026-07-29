"""
Docker Unix socket 连接工具模块。

通过 HTTPX 异步客户端与 Docker daemon Unix socket 通信。
"""

import httpx

from app.core.config import (
    ADMIN_PASS_HEADER,
    ADMIN_USER_HEADER,
    API_KEY_NAME,
    DOCKER_SOCKET_PATH,
)

# 转发到 Docker daemon 时需要移除的请求头
_FORWARD_EXCLUDED_HEADERS = {
    API_KEY_NAME.lower(),
    ADMIN_USER_HEADER.lower(),
    ADMIN_PASS_HEADER.lower(),
    "host",
    "content-length",
    "transfer-encoding",
}

_client: httpx.AsyncClient | None = None


def _filter_headers(headers: dict) -> dict:
    """移除认证头，其余请求头转为小写返回。"""
    return {
        k.lower(): v
        for k, v in headers.items()
        if k.lower() not in _FORWARD_EXCLUDED_HEADERS
    }


def get_docker_http_client() -> httpx.AsyncClient:
    """获取复用的 Docker daemon HTTPX 客户端，懒初始化。"""
    global _client
    if _client is None:
        transport = httpx.AsyncHTTPTransport(uds=DOCKER_SOCKET_PATH)
        _client = httpx.AsyncClient(transport=transport)
    return _client


async def close_docker_http_client():
    """关闭 Docker HTTPX 客户端连接池。"""
    global _client
    if _client is not None:
        await _client.aclose()
        _client = None
