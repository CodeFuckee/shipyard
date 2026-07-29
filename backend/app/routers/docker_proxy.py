"""
Docker Engine API 代理路由器。

将符合 Docker Engine API 路径格式（/v1.{version}/{path}）的请求
透传到 Docker daemon Unix socket，不做任何业务层处理。
"""

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse

from app.core.security import get_api_key
from app.core.docker_socket import _filter_headers, get_docker_http_client

router = APIRouter(
    tags=["docker-engine-api"],
    dependencies=[Depends(get_api_key)],
)


@router.api_route(
    "/v1{path:path}",
    methods=["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"],
)
async def proxy_docker_api(request: Request, path: str):
    docker_api_path = f"/v1{path}"
    query_string = f"?{request.url.query}" if request.url.query else ""
    full_url = f"http://localhost{docker_api_path}{query_string}"

    headers = _filter_headers(dict(request.headers))
    client = get_docker_http_client()

    try:
        async with client.stream(
            method=request.method,
            url=full_url,
            headers=headers,
            content=_stream_request_body(request),
        ) as resp:
            return StreamingResponse(
                content=resp.aiter_bytes(),
                status_code=resp.status_code,
                headers=resp.headers,
                media_type=resp.headers.get("content-type"),
            )
    except httpx.ConnectError as e:
        raise HTTPException(status_code=502, detail=f"无法连接 Docker daemon: {e}")
    except httpx.TimeoutException as e:
        raise HTTPException(status_code=504, detail=f"Docker daemon 请求超时: {e}")


async def _stream_request_body(request: Request):
    async for chunk in request.stream():
        yield chunk
