"""app.core.docker_socket 模块单元测试。"""

import pytest
from app.core.docker_socket import _filter_headers


class TestFilterHeaders:
    """测试 _filter_headers 请求头过滤逻辑。"""

    def test_strips_auth_headers(self):
        """验证 Mobile Portainer 认证头被移除，其余头保留。"""
        headers = {
            "X-API-Key": "secret",
            "X-Admin-User": "admin",
            "X-Admin-Pass": "pass",
            "Content-Type": "application/json",
            "Accept": "*/*",
        }
        result = _filter_headers(headers)
        assert "x-api-key" not in result
        assert "x-admin-user" not in result
        assert "x-admin-pass" not in result
        assert result["content-type"] == "application/json"
        assert result["accept"] == "*/*"

    def test_preserves_docker_registry_auth(self):
        """验证 Docker registry 认证头 X-Registry-Auth 被保留。"""
        headers = {
            "X-Registry-Auth": "base64encodedtoken",
            "Content-Type": "application/json",
        }
        result = _filter_headers(headers)
        assert "x-registry-auth" in result
        assert result["x-registry-auth"] == "base64encodedtoken"

    def test_strips_host_and_transfer_headers(self):
        """验证 host、content-length、transfer-encoding 被移除。"""
        headers = {
            "Host": "example.com",
            "Content-Length": "100",
            "Transfer-Encoding": "chunked",
            "Content-Type": "text/plain",
        }
        result = _filter_headers(headers)
        assert "host" not in result
        assert "content-length" not in result
        assert "transfer-encoding" not in result
        assert result["content-type"] == "text/plain"

    def test_empty_headers(self):
        """空请求头返回空字典。"""
        assert _filter_headers({}) == {}
