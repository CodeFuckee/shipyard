"""字体缓存代理（/fonts）集成测试。

验证：磁盘持久化缓存命中/回源下载、路径白名单校验（防 SSRF/路径穿越）、
回源失败处理、并发安全、缓存目录自动创建、Content-Type 映射。
"""

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest
from httpx import ASGITransport, AsyncClient, Response

from app.core.config import FONTS_CACHE_DIR
from main import app

# 与真实 Noto Sans SC 分块字体同构的路径（v37 版本 + 分块编号）
FONT_PATH = (
    "s/notosanssc/v37/"
    "k3kCo84MPvpLmixcA63oeAL7Iqp5IZJF9bmaG9_FnYkldv7JjxkkgFsFSSOPMOkySAZ73y9ViAt3acb8NexQ2w.113.woff2"
)
UPSTREAM_URL = f"https://fonts.gstatic.com/{FONT_PATH}"
FONT_BYTES = b"\x00\x01\x00\x00font-test-data"


@pytest.fixture
def font_cache_dir(tmp_path):
    """把字体缓存目录指向临时目录，隔离真实 data/fonts。"""
    with patch("app.routers.fonts.FONTS_CACHE_DIR", new=str(tmp_path)):
        yield tmp_path


@pytest.fixture
def mock_upstream(font_cache_dir):
    """mock 回源 httpx client，默认返回 200 字体内容。"""
    client = MagicMock()
    client.get = AsyncMock(
        return_value=Response(
            200,
            content=FONT_BYTES,
            headers={"Content-Type": "font/woff2"},
        )
    )
    with patch("app.routers.fonts._get_client", return_value=client):
        yield client


class TestFontProxyNormal:
    """正常路径：回源下载、磁盘缓存、二次命中。"""

    def test_fonts_endpoint_requires_no_auth(self, client, mock_upstream):
        """字体端点必须公开（浏览器加载字体无法携带 API Key）。"""
        resp = client.get(f"/fonts/{FONT_PATH}")
        assert resp.status_code == 200
        assert resp.content == FONT_BYTES

    def test_miss_then_cache_hit_only_one_download(self, client, mock_upstream):
        """首次未命中回源一次，后续请求全部命中缓存。"""
        for _ in range(3):
            resp = client.get(f"/fonts/{FONT_PATH}")
            assert resp.status_code == 200
            assert resp.content == FONT_BYTES
        mock_upstream.get.assert_awaited_once_with(UPSTREAM_URL)

    def test_upstream_url_built_correctly(self, client, mock_upstream):
        """回源 URL 拼接正确（域名 + 完整路径）。"""
        client.get(f"/fonts/{FONT_PATH}")
        mock_upstream.get.assert_awaited_once_with(UPSTREAM_URL)

    def test_download_persisted_to_disk(self, client, mock_upstream, font_cache_dir):
        """回源成功后字体落盘到缓存目录（含子目录结构）。"""
        client.get(f"/fonts/{FONT_PATH}")
        disk_file = font_cache_dir / FONT_PATH
        assert disk_file.is_file()
        assert disk_file.read_bytes() == FONT_BYTES

    def test_cached_file_skips_download(self, client, mock_upstream, font_cache_dir):
        """缓存文件已存在时直接返回磁盘内容，不回源。"""
        disk_file = font_cache_dir / FONT_PATH
        disk_file.parent.mkdir(parents=True)
        disk_file.write_bytes(b"pre-cached-content")
        resp = client.get(f"/fonts/{FONT_PATH}")
        assert resp.status_code == 200
        assert resp.content == b"pre-cached-content"
        mock_upstream.get.assert_not_awaited()

    def test_woff2_content_type(self, client, mock_upstream):
        """woff2 返回标准 MIME（RFC 8081）。"""
        resp = client.get(f"/fonts/{FONT_PATH}")
        assert resp.headers["content-type"] == "font/woff2"

    def test_ttf_content_type(self, client, mock_upstream):
        """ttf 返回 font/ttf。"""
        ttf_path = "s/somefont/v1/example.abc.ttf"
        mock_upstream.get.return_value = Response(
            200, content=FONT_BYTES, headers={"Content-Type": "font/ttf"}
        )
        resp = client.get(f"/fonts/{ttf_path}")
        assert resp.status_code == 200
        assert resp.headers["content-type"] == "font/ttf"


class TestFontProxyInvalidPath:
    """路径白名单校验：防 SSRF 与路径穿越。"""

    @pytest.mark.parametrize(
        "path",
        [
            "foo/bar.woff2",  # 不以 s/ 开头
            "s/notosanssc/v37/xxx.html",  # 非字体扩展名
            "s/notosanssc/v37/xxx.png",
            "s/notosanssc/v37/xxx",  # 无扩展名
            "s/notosanssc/v37/xxx.woff2.exe",  # 伪造扩展名结尾
        ],
    )
    def test_invalid_path_rejected(self, client, mock_upstream, path):
        resp = client.get(f"/fonts/{path}")
        assert resp.status_code == 404
        mock_upstream.get.assert_not_awaited()

    def test_dot_dot_traversal_rejected(self, client, mock_upstream):
        """未编码 .. 段：无论 httpx 是否规范化，都必须 404 且不回源。"""
        resp = client.get("/fonts/s/../evil.woff2")
        assert resp.status_code == 404
        mock_upstream.get.assert_not_awaited()

    def test_encoded_dot_dot_traversal_rejected(self, client, mock_upstream):
        """URL 编码的 .. 必须被解码后校验并拒绝。"""
        resp = client.get("/fonts/s/%2e%2e/evil.woff2")
        assert resp.status_code == 404
        mock_upstream.get.assert_not_awaited()

    def test_empty_path_rejected(self, client, mock_upstream):
        """空路径返回 404。"""
        resp = client.get("/fonts/")
        assert resp.status_code == 404
        mock_upstream.get.assert_not_awaited()

    def test_windows_backslash_rejected(self, client, mock_upstream):
        """反斜杠路径（Windows 风格穿越）拒绝。"""
        resp = client.get("/fonts/s%5C..%5Cevil.woff2")
        assert resp.status_code == 404
        mock_upstream.get.assert_not_awaited()


class TestFontProxyUpstreamFailure:
    """回源失败：返回 404、不落盘、不留脏缓存。"""

    @pytest.mark.parametrize("status", [404, 500, 403, 301])
    def test_upstream_non_200_returns_404(self, client, mock_upstream, font_cache_dir, status):
        mock_upstream.get.return_value = Response(status, content=b"oops")
        resp = client.get(f"/fonts/{FONT_PATH}")
        assert resp.status_code == 404
        assert not (font_cache_dir / FONT_PATH).exists()

    def test_upstream_connect_error_returns_404(self, client, mock_upstream, font_cache_dir):
        mock_upstream.get.side_effect = httpx.ConnectError("connection refused")
        resp = client.get(f"/fonts/{FONT_PATH}")
        assert resp.status_code == 404
        assert not (font_cache_dir / FONT_PATH).exists()

    def test_upstream_timeout_returns_404(self, client, mock_upstream, font_cache_dir):
        mock_upstream.get.side_effect = httpx.TimeoutException("timed out")
        resp = client.get(f"/fonts/{FONT_PATH}")
        assert resp.status_code == 404
        assert not (font_cache_dir / FONT_PATH).exists()

    def test_upstream_empty_content_not_cached(self, client, mock_upstream, font_cache_dir):
        """0 字节响应视为无效字体，不缓存。"""
        mock_upstream.get.return_value = Response(200, content=b"")
        resp = client.get(f"/fonts/{FONT_PATH}")
        assert resp.status_code == 404
        assert not (font_cache_dir / FONT_PATH).exists()

    def test_failure_then_success_recovers(self, client, mock_upstream, font_cache_dir):
        """先失败后成功：失败不污染缓存，成功后可正常缓存。"""
        mock_upstream.get.side_effect = [
            httpx.ConnectError("down"),
            Response(200, content=FONT_BYTES, headers={"Content-Type": "font/woff2"}),
        ]
        resp = client.get(f"/fonts/{FONT_PATH}")
        assert resp.status_code == 404
        resp = client.get(f"/fonts/{FONT_PATH}")
        assert resp.status_code == 200
        assert (font_cache_dir / FONT_PATH).read_bytes() == FONT_BYTES


class TestFontProxyCacheDir:
    def test_cache_dir_auto_created(self, client, mock_upstream, font_cache_dir):
        """缓存目录不存在时自动创建（含多级子目录）。"""
        import shutil

        shutil.rmtree(font_cache_dir)
        resp = client.get(f"/fonts/{FONT_PATH}")
        assert resp.status_code == 200
        assert (font_cache_dir / FONT_PATH).is_file()


class TestFontProxyConcurrency:
    """并发安全：原子写保证文件完整，无脏数据。"""

    async def test_concurrent_same_font_all_succeed(self, mock_upstream, font_cache_dir):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://testserver") as ac:
            results = await asyncio.gather(
                *(ac.get(f"/fonts/{FONT_PATH}") for _ in range(5))
            )
        for resp in results:
            assert resp.status_code == 200
            assert resp.content == FONT_BYTES
        assert (font_cache_dir / FONT_PATH).read_bytes() == FONT_BYTES

    async def test_concurrent_different_fonts(self, mock_upstream, font_cache_dir):
        transport = ASGITransport(app=app)
        paths = [f"s/font{i}/v1/abc.def.{i}.woff2" for i in range(4)]
        async with AsyncClient(transport=transport, base_url="http://testserver") as ac:
            results = await asyncio.gather(*(ac.get(f"/fonts/{p}") for p in paths))
        for resp in results:
            assert resp.status_code == 200
            assert resp.content == FONT_BYTES
        for p in paths:
            assert (font_cache_dir / p).read_bytes() == FONT_BYTES
