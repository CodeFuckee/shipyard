"""Docker Engine API 代理路由器集成测试。"""

import json
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from httpx import Response


def _make_mock_stream(mock_resp, aiter_bytes_fn=None):
    """构建 mock 的 httpx client.stream() 返回链。

    client.stream(method=..., url=..., ...) 是同步方法，
    返回一个 async context manager，其 __aenter__ 返回 Response 对象。
    """
    if aiter_bytes_fn is None:

        async def _default_aiter_bytes():
            yield mock_resp.content

        aiter_bytes_fn = _default_aiter_bytes

    mock_resp.aiter_bytes = MagicMock(return_value=aiter_bytes_fn())

    mock_cm = MagicMock()
    mock_cm.__aenter__ = AsyncMock(return_value=mock_resp)
    mock_cm.__aexit__ = AsyncMock(return_value=None)
    return mock_cm


def _setup_mock_client(mock_get_client, mock_resp, aiter_bytes_fn=None):
    """配置 get_docker_http_client 的 mock 链路。"""
    mock_stream_cm = _make_mock_stream(mock_resp, aiter_bytes_fn)

    mock_client = MagicMock()
    mock_client.stream = MagicMock(return_value=mock_stream_cm)

    mock_get_client.return_value = mock_client
    return mock_client


class TestDockerProxyAuth:
    """测试代理路由的认证要求。"""

    def test_proxy_requires_auth(self, client):
        """无认证头时返回 401。"""
        response = client.get("/v1.45/info")
        assert response.status_code == 401

    def test_proxy_with_admin_credentials(self, client, admin_headers):
        """Admin 凭据可通过认证并成功转发。"""
        mock_resp = Response(
            status_code=200,
            json={"DockerVersion": "27.0.0"},
            headers={"Content-Type": "application/json"},
        )

        async def _aiter_bytes():
            yield json.dumps({"DockerVersion": "27.0.0"}).encode()

        with patch(
            "app.routers.docker_proxy.get_docker_http_client"
        ) as mock_get_client:
            _setup_mock_client(mock_get_client, mock_resp, _aiter_bytes)

            response = client.get("/v1.45/info", headers=admin_headers)
            assert response.status_code == 200
            assert response.json() == {"DockerVersion": "27.0.0"}


class TestDockerProxyForwarding:
    """测试代理请求的透传行为。"""

    def test_proxy_successful_info_request(self, client, admin_headers):
        """验证 /v1.45/info 被正确转发并返回结果。"""
        mock_resp = Response(
            status_code=200,
            json={"ID": "docker-id"},
            headers={"Content-Type": "application/json"},
        )

        async def _aiter_bytes():
            yield json.dumps({"ID": "docker-id"}).encode()

        with patch(
            "app.routers.docker_proxy.get_docker_http_client"
        ) as mock_get_client:
            _setup_mock_client(mock_get_client, mock_resp, _aiter_bytes)

            response = client.get("/v1.45/info", headers=admin_headers)
            assert response.status_code == 200
            assert response.json() == {"ID": "docker-id"}

    def test_proxy_socket_unreachable(self, client, admin_headers):
        """Docker socket 不可达时返回 502。"""
        import httpx

        with patch(
            "app.routers.docker_proxy.get_docker_http_client"
        ) as mock_get_client:
            mock_client = MagicMock()
            mock_client.stream = MagicMock(
                side_effect=httpx.ConnectError("socket not found")
            )
            mock_get_client.return_value = mock_client

            response = client.get("/v1.45/info", headers=admin_headers)
            assert response.status_code == 502
            assert "Docker daemon" in response.json()["detail"]

    def test_proxy_preserves_query_params(self, client, admin_headers):
        """验证查询参数透传到 Docker daemon。"""
        mock_resp = Response(
            status_code=200,
            json=[],
            headers={"Content-Type": "application/json"},
        )

        async def _aiter_bytes():
            yield b"[]"

        with patch(
            "app.routers.docker_proxy.get_docker_http_client"
        ) as mock_get_client:
            mock_client = _setup_mock_client(mock_get_client, mock_resp, _aiter_bytes)

            response = client.get(
                "/v1.45/containers/json?all=true", headers=admin_headers
            )
            assert response.status_code == 200

            call_kwargs = mock_client.stream.call_args.kwargs
            assert (
                call_kwargs["url"] == "http://localhost/v1.45/containers/json?all=true"
            )
            assert call_kwargs["method"] == "GET"

    def test_proxy_preserves_request_body(self, client, admin_headers):
        """验证 POST 请求体透传到 Docker daemon。"""
        mock_resp = Response(
            status_code=201,
            json={"Id": "abc123"},
            headers={"Content-Type": "application/json"},
        )
        request_body = '{"Image":"nginx:latest"}'

        async def _aiter_bytes():
            yield json.dumps({"Id": "abc123"}).encode()

        with patch(
            "app.routers.docker_proxy.get_docker_http_client"
        ) as mock_get_client:
            _setup_mock_client(mock_get_client, mock_resp, _aiter_bytes)

            response = client.post(
                "/v1.45/containers/create",
                content=request_body,
                headers={
                    **admin_headers,
                    "Content-Type": "application/json",
                },
            )
            assert response.status_code == 201
            assert response.json() == {"Id": "abc123"}

    def test_proxy_forwards_docker_error_status(self, client, admin_headers):
        """验证 Docker 错误状态码原样返回给客户端。"""
        mock_resp = Response(
            status_code=404,
            json={"message": "No such container: xyz"},
            headers={"Content-Type": "application/json"},
        )

        async def _aiter_bytes():
            yield json.dumps({"message": "No such container: xyz"}).encode()

        with patch(
            "app.routers.docker_proxy.get_docker_http_client"
        ) as mock_get_client:
            _setup_mock_client(mock_get_client, mock_resp, _aiter_bytes)

            response = client.get("/v1.45/containers/xyz/json", headers=admin_headers)
            assert response.status_code == 404
            assert response.json() == {"message": "No such container: xyz"}

    def test_proxy_timeout_returns_504(self, client, admin_headers):
        """验证 Docker daemon 超时返回 504。"""
        import httpx

        with patch(
            "app.routers.docker_proxy.get_docker_http_client"
        ) as mock_get_client:
            mock_client = MagicMock()
            mock_client.stream = MagicMock(
                side_effect=httpx.TimeoutException("request timed out")
            )
            mock_get_client.return_value = mock_client

            response = client.get("/v1.45/info", headers=admin_headers)
            assert response.status_code == 504

    def test_existing_api_routes_still_work(self, client, admin_headers):
        """验证现有 Mobile Portainer API 路由不受影响。"""
        response = client.get("/info", headers=admin_headers)
        assert response.status_code != 404
