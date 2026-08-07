"""
Google Fonts 字体缓存代理路由器。

Flutter Web 的 CanvasKit 引擎渲染中文文本时，会从 fonts.gstatic.com 下载
Noto Sans SC 分块字体文件（国内无法访问）。前端通过 Service Worker 将
字体请求改写为同源 /fonts/{path}，本路由提供磁盘持久化缓存：
命中直接返回本地文件，未命中再回源 fonts.gstatic.com 下载并落盘。

缓存策略：永久缓存。字体 URL 带版本 hash（如 v37），同一路径内容不变，
未命中才回源，回源失败返回 404（浏览器 fallback 到系统字体，页面仍可用）。
"""

import pathlib
import uuid

import httpx
from fastapi import APIRouter, HTTPException, Response
from fastapi.responses import FileResponse

from app.core.config import FONTS_CACHE_DIR

router = APIRouter(tags=["fonts"])

UPSTREAM_BASE = "https://fonts.gstatic.com"

# 白名单字体扩展名（防任意文件路径代理）
_FONT_EXTENSIONS = {".woff2", ".woff", ".ttf", ".otf"}
# 字体 MIME 映射（RFC 8081）
_FONT_MEDIA_TYPES = {
    ".woff2": "font/woff2",
    ".woff": "font/woff",
    ".ttf": "font/ttf",
    ".otf": "font/otf",
}

_client: httpx.AsyncClient | None = None


def _get_client() -> httpx.AsyncClient:
    """获取全局回源 HTTP 客户端（懒加载单例）。"""
    global _client
    if _client is None:
        _client = httpx.AsyncClient(timeout=30.0, follow_redirects=False)
    return _client


def _is_valid_font_path(path: str) -> bool:
    """校验字体路径：以 s/ 开头、禁止路径穿越、以白名单扩展名结尾。"""
    if not path or not path.startswith("s/") or ".." in path or "\\" in path:
        return False
    return pathlib.Path(path).suffix.lower() in _FONT_EXTENSIONS


async def _download_font(path: str) -> bytes | None:
    """回源 fonts.gstatic.com 下载字体。

    非 200 响应、空内容、网络异常均返回 None（调用方返回 404 且不落盘）。
    """
    try:
        resp = await _get_client().get(f"{UPSTREAM_BASE}/{path}")
    except httpx.HTTPError:
        return None
    if resp.status_code != 200 or not resp.content:
        return None
    return resp.content


@router.get("/fonts/{path:path}")
async def get_font(path: str):
    """字体代理：磁盘缓存命中直接返回，未命中回源下载并持久化。"""
    if not _is_valid_font_path(path):
        raise HTTPException(status_code=404, detail="Font not found")

    cache_file = pathlib.Path(FONTS_CACHE_DIR) / path
    media_type = _FONT_MEDIA_TYPES[cache_file.suffix.lower()]
    if cache_file.is_file():
        return FileResponse(cache_file, media_type=media_type)

    content = await _download_font(path)
    if content is None:
        raise HTTPException(status_code=404, detail="Font not found")

    cache_file.parent.mkdir(parents=True, exist_ok=True)
    # 原子写入：临时文件 + rename，避免并发请求读到半截文件
    tmp_file = cache_file.with_name(f"{cache_file.name}.tmp{uuid.uuid4().hex}")
    tmp_file.write_bytes(content)
    tmp_file.rename(cache_file)

    return Response(content=content, media_type=media_type)
