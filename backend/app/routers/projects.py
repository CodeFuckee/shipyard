"""
项目 API 路由 — Docker 项目管理（Dockerfile 编辑、镜像构建、compose 启停）。

端点概览:
- GET    /projects                   项目列表
- POST   /projects                   创建项目
- GET    /projects/{id}              项目详情
- DELETE /projects/{id}              删除项目
- GET    /projects/{id}/files/{fn}    获取文件内容
- PUT    /projects/{id}/files/{fn}    更新文件内容
- POST   /projects/{id}/build        触发构建
- POST   /projects/{id}/up           docker-compose up
- POST   /projects/{id}/down         docker-compose down
- WS     /ws/projects/{id}/build/logs 构建日志推送
"""

from __future__ import annotations

import asyncio
import json
import os
import pathlib
import re
import shutil
import subprocess
import uuid
from datetime import datetime, timezone
from typing import Any

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Query,
    WebSocket,
    WebSocketDisconnect,
    status,
)
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.core.config import PROJECTS_DIR
from app.core.security import get_api_key
from app.core.utils import get_docker_client
from app.db.database import SessionLocal, get_db
from app.db.models import APIKeyModel, ProjectModel

# ---------------------------------------------------------------------------
# Pydantic schemas
# ---------------------------------------------------------------------------


class CreateProjectRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=128, description="项目名称")
    description: str | None = Field(
        default=None, max_length=512, description="项目描述"
    )


class UpdateFileRequest(BaseModel):
    content: str = Field(..., description="文件内容")


class ProjectResponse(BaseModel):
    id: str
    name: str
    description: str | None
    status: str
    createdAt: str | None = None
    updatedAt: str | None = None

    model_config = {"from_attributes": True}


# ---------------------------------------------------------------------------
# 默认模板
# ---------------------------------------------------------------------------

DEFAULT_DOCKERFILE = """\
FROM alpine:latest

# 设置工作目录
WORKDIR /app

# 复制文件（根据需要修改）
# COPY . .

# 运行命令（根据需要修改）
# CMD ["echo", "Hello World"]
"""

DEFAULT_COMPOSE_YAML = """\
version: '3.8'

services:
  app:
    build: .
    # ports:
    #   - "8080:80"
    # volumes:
    #   - ./data:/app/data
    # environment:
    #   - NODE_ENV=production
"""

# ---------------------------------------------------------------------------
# 构建日志分发 — 项目级别的 asyncio.Queue 广播
# ---------------------------------------------------------------------------

# 每个项目维护一组 WebSocket 队列
_build_queues: dict[str, list[asyncio.Queue[dict]]] = {}
# 正在运行的构建任务
_build_tasks: dict[str, asyncio.Task[None]] = {}


def _get_queues(project_id: str) -> list[asyncio.Queue[dict]]:
    """获取（必要时创建）项目的 WebSocket 队列列表。"""
    if project_id not in _build_queues:
        _build_queues[project_id] = []
    return _build_queues[project_id]


async def _broadcast(project_id: str, message: dict) -> None:
    """将消息推送到项目所有已连接的 WebSocket 客户端。"""
    queues = _get_queues(project_id)
    dead: list[asyncio.Queue[dict]] = []
    for q in queues:
        try:
            q.put_nowait(message)
        except asyncio.QueueFull:
            dead.append(q)
    for q in dead:
        try:
            queues.remove(q)
        except ValueError:
            pass


# ---------------------------------------------------------------------------
# 辅助函数
# ---------------------------------------------------------------------------


def _project_dir(project_id: str) -> pathlib.Path:
    """返回项目的文件存储目录。"""
    return pathlib.Path(PROJECTS_DIR) / project_id


def _ensure_project_dir(project_id: str) -> pathlib.Path:
    """确保项目目录存在并返回路径。"""
    d = _project_dir(project_id)
    d.mkdir(parents=True, exist_ok=True)
    return d


def _model_to_dict(p: ProjectModel) -> dict[str, Any]:
    """将 SQLAlchemy 模型转为 API 响应字典。"""
    return {
        "id": p.id,
        "name": p.name,
        "description": p.description,
        "status": p.status,
        "createdAt": p.created_at.isoformat() if p.created_at else None,
        "updatedAt": p.updated_at.isoformat() if p.updated_at else None,
    }


def _utcnow() -> str:
    return datetime.now(timezone.utc).isoformat()


# ---------------------------------------------------------------------------
# 构建执行（在后台线程中运行 docker build）
# ---------------------------------------------------------------------------


def _run_build_sync(project_id: str, event_loop: asyncio.AbstractEventLoop):
    """在同步线程中执行 docker build，将输出通过 asyncio.Queue 广播。"""
    project_dir = _project_dir(project_id)
    dockerfile_path = project_dir / "Dockerfile"

    client = get_docker_client()
    db = SessionLocal()

    try:
        # ---- 更新状态为 building ----
        project = db.query(ProjectModel).filter(ProjectModel.id == project_id).first()
        if project:
            project.status = "building"
            project.updated_at = datetime.now(timezone.utc)
            db.commit()

        # ---- 发送开始消息 ----
        asyncio.run_coroutine_threadsafe(
            _broadcast(
                project_id,
                {
                    "stream": "Starting build...\n",
                    "status": "Building",
                    "error": None,
                    "imageId": None,
                    "isDone": False,
                },
            ),
            event_loop,
        )

        # ---- 检查 Dockerfile ----
        if not dockerfile_path.exists():
            asyncio.run_coroutine_threadsafe(
                _broadcast(
                    project_id,
                    {
                        "stream": None,
                        "status": None,
                        "error": "Dockerfile 不存在",
                        "imageId": None,
                        "isDone": True,
                    },
                ),
                event_loop,
            )
            if project:
                project.status = "failed"
                project.updated_at = datetime.now(timezone.utc)
                db.commit()
            return

        # 读取 Dockerfile 内容以做空文件检查
        dockerfile_content = dockerfile_path.read_text(encoding="utf-8").strip()
        if not dockerfile_content:
            asyncio.run_coroutine_threadsafe(
                _broadcast(
                    project_id,
                    {
                        "stream": None,
                        "status": None,
                        "error": "Dockerfile 为空",
                        "imageId": None,
                        "isDone": True,
                    },
                ),
                event_loop,
            )
            if project:
                project.status = "failed"
                project.updated_at = datetime.now(timezone.utc)
                db.commit()
            return

        # ---- 执行构建 ----
        image_id: str | None = None

        for chunk in client.api.build(
            path=str(project_dir),
            dockerfile="Dockerfile",
            tag=f"mobile_portainer_proj_{project_id}:latest",
            rm=True,
            decode=True,
        ):
            msg: dict[str, Any] = {
                "stream": None,
                "status": None,
                "error": None,
                "imageId": None,
                "isDone": False,
            }

            if "stream" in chunk:
                msg["stream"] = chunk["stream"]
            elif "status" in chunk:
                msg["status"] = chunk["status"]
                # 尝试从状态中提取 image ID
                if "aux" in chunk and "ID" in chunk["aux"]:
                    image_id = chunk["aux"]["ID"]
                    msg["imageId"] = image_id
            elif "error" in chunk:
                msg["error"] = chunk["error"]
                msg["isDone"] = True
            elif "message" in chunk:
                msg["error"] = chunk["message"]
                msg["isDone"] = True

            # 检测是否构建成功完成
            if msg.get("stream") and "Successfully built" in (msg["stream"] or ""):
                m = re.search(r"Successfully built\s+([a-f0-9]+)", msg["stream"])
                if m:
                    image_id = m.group(1)
                    msg["imageId"] = image_id
            elif msg.get("status") and "Successfully built" in (msg["status"] or ""):
                m = re.search(r"Successfully built\s+([a-f0-9]+)", msg["status"])
                if m:
                    image_id = m.group(1)
                    msg["imageId"] = image_id

            asyncio.run_coroutine_threadsafe(_broadcast(project_id, msg), event_loop)

        # ---- 构建成功 ----
        asyncio.run_coroutine_threadsafe(
            _broadcast(
                project_id,
                {
                    "stream": None,
                    "status": "Build completed",
                    "error": None,
                    "imageId": image_id,
                    "isDone": True,
                },
            ),
            event_loop,
        )

        if project:
            project.status = "idle"
            project.updated_at = datetime.now(timezone.utc)
            db.commit()

    except Exception as exc:
        asyncio.run_coroutine_threadsafe(
            _broadcast(
                project_id,
                {
                    "stream": None,
                    "status": None,
                    "error": f"构建失败: {exc}",
                    "imageId": None,
                    "isDone": True,
                },
            ),
            event_loop,
        )
        # 更新状态为 failed
        if project:
            project.status = "failed"
            project.updated_at = datetime.now(timezone.utc)
            db.commit()
    finally:
        client.close()
        db.close()
        _build_tasks.pop(project_id, None)


# ---------------------------------------------------------------------------
# 路由
# ---------------------------------------------------------------------------

router = APIRouter(
    prefix="/projects",
    tags=["projects"],
    dependencies=[Depends(get_api_key)],
)


# -- 辅助路由：构建日志 WebSocket（注册在 /ws 前缀下，无 API Key 依赖）----------

ws_router = APIRouter(prefix="/ws", tags=["websockets"])


@ws_router.websocket("/projects/{project_id}/build/logs")
async def websocket_build_logs(
    websocket: WebSocket, project_id: str, api_key: str = Query(...)
):
    """
    WebSocket — 实时推送项目构建日志。

    连接: ws://host:port/ws/projects/{id}/build/logs?api_key={key}
    """
    await websocket.accept()

    # ---- 校验 API Key ----
    db = SessionLocal()
    try:
        if not api_key:
            await websocket.close(
                code=status.WS_1008_POLICY_VIOLATION, reason="missing api_key"
            )
            return
        key_record = db.query(APIKeyModel).filter(APIKeyModel.key == api_key).first()
        if not key_record:
            await websocket.close(
                code=status.WS_1008_POLICY_VIOLATION, reason="invalid api_key"
            )
            return
    finally:
        db.close()

    # ---- 检查项目是否存在 ----
    db = SessionLocal()
    try:
        project = db.query(ProjectModel).filter(ProjectModel.id == project_id).first()
        if not project:
            await websocket.send_json(
                {
                    "stream": None,
                    "status": None,
                    "error": "项目不存在",
                    "imageId": None,
                    "isDone": True,
                }
            )
            await websocket.close()
            return
    finally:
        db.close()

    # ---- 订阅构建日志 ----
    queue: asyncio.Queue[dict] = asyncio.Queue(maxsize=256)
    queues = _get_queues(project_id)
    queues.append(queue)

    try:
        while True:
            try:
                msg = await asyncio.wait_for(queue.get(), timeout=30)
            except asyncio.TimeoutError:
                # 发送心跳保持连接
                try:
                    await websocket.send_json(
                        {
                            "stream": None,
                            "status": "Waiting for build...",
                            "error": None,
                            "imageId": None,
                            "isDone": False,
                        }
                    )
                except Exception:
                    break
                continue

            try:
                await websocket.send_json(msg)
            except Exception:
                break

            if msg.get("isDone"):
                break
    except WebSocketDisconnect:
        pass
    finally:
        try:
            queues.remove(queue)
        except ValueError:
            pass
        try:
            await websocket.close()
        except Exception:
            pass


# -- REST 端点 ----------------------------------------------------------------


@router.get("", response_model=list[dict])
def list_projects(db: Session = Depends(get_db)):
    """获取所有项目列表。"""
    try:
        projects = db.query(ProjectModel).order_by(ProjectModel.updated_at.desc()).all()
        return [_model_to_dict(p) for p in projects]
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"获取项目列表失败: {e}")


@router.post("", response_model=dict, status_code=201)
def create_project(data: CreateProjectRequest, db: Session = Depends(get_db)):
    """创建新项目，自动生成默认 Dockerfile 和 docker-compose.yaml。"""
    # 检查重名
    existing = db.query(ProjectModel).filter(ProjectModel.name == data.name).first()
    if existing:
        raise HTTPException(status_code=400, detail="项目名称已存在")

    project_id = f"proj_{uuid.uuid4().hex[:12]}"
    now = datetime.now(timezone.utc)

    project = ProjectModel(
        id=project_id,
        name=data.name,
        description=data.description,
        status="idle",
        created_at=now,
        updated_at=now,
    )
    db.add(project)
    db.commit()
    db.refresh(project)

    # ---- 创建项目目录和默认文件 ----
    project_dir = _ensure_project_dir(project_id)
    (project_dir / "Dockerfile").write_text(DEFAULT_DOCKERFILE, encoding="utf-8")
    (project_dir / "docker-compose.yaml").write_text(
        DEFAULT_COMPOSE_YAML, encoding="utf-8"
    )

    return _model_to_dict(project)


@router.get("/{project_id}", response_model=dict)
def get_project(project_id: str, db: Session = Depends(get_db)):
    """获取项目详情。"""
    project = db.query(ProjectModel).filter(ProjectModel.id == project_id).first()
    if not project:
        raise HTTPException(status_code=404, detail="项目不存在")
    return _model_to_dict(project)


@router.delete("/{project_id}", response_model=dict)
def delete_project(project_id: str, db: Session = Depends(get_db)):
    """删除项目及其关联的所有文件。"""
    project = db.query(ProjectModel).filter(ProjectModel.id == project_id).first()
    if not project:
        raise HTTPException(status_code=404, detail="项目不存在")

    # 检查是否正在构建
    if project.status == "building":
        raise HTTPException(status_code=409, detail="项目正在构建中，无法删除")

    # 先尝试 stop + down（如果正在 running）
    compose_file = _project_dir(project_id) / "docker-compose.yaml"
    if compose_file.exists():
        try:
            subprocess.run(
                [
                    "docker",
                    "compose",
                    "-f",
                    str(compose_file),
                    "-p",
                    f"mp_{project_id}",
                    "down",
                    "--volumes",
                ],
                capture_output=True,
                timeout=30,
            )
        except Exception:
            pass  # 删除操作尽力而为

    db.delete(project)
    db.commit()

    # 删除项目目录
    project_dir = _project_dir(project_id)
    if project_dir.exists():
        try:
            shutil.rmtree(str(project_dir))
        except OSError:
            pass

    return {"status": "deleted"}


# -- 文件操作 ----------------------------------------------------------------


@router.get("/{project_id}/files/{filename}", response_model=dict)
def get_project_file(project_id: str, filename: str, db: Session = Depends(get_db)):
    """获取项目文件内容（Dockerfile 或 docker-compose.yaml）。"""
    project = db.query(ProjectModel).filter(ProjectModel.id == project_id).first()
    if not project:
        raise HTTPException(status_code=404, detail="项目不存在")

    allowed = {"Dockerfile", "docker-compose.yaml"}
    if filename not in allowed:
        raise HTTPException(
            status_code=400, detail=f"不支持的文件名: {filename}，仅支持 {allowed}"
        )

    file_path = _project_dir(project_id) / filename
    if not file_path.exists():
        raise HTTPException(status_code=404, detail=f"文件 {filename} 不存在")

    return {
        "filename": filename,
        "content": file_path.read_text(encoding="utf-8"),
    }


@router.put("/{project_id}/files/{filename}", response_model=dict)
def update_project_file(
    project_id: str,
    filename: str,
    data: UpdateFileRequest,
    db: Session = Depends(get_db),
):
    """更新项目文件内容（Dockerfile 或 docker-compose.yaml）。"""
    project = db.query(ProjectModel).filter(ProjectModel.id == project_id).first()
    if not project:
        raise HTTPException(status_code=404, detail="项目不存在")

    allowed = {"Dockerfile", "docker-compose.yaml"}
    if filename not in allowed:
        raise HTTPException(
            status_code=400, detail=f"不支持的文件名: {filename}，仅支持 {allowed}"
        )

    if data.content is None:
        raise HTTPException(status_code=400, detail="content 字段为必填项")

    file_path = _project_dir(project_id) / filename
    file_path.write_text(data.content, encoding="utf-8")

    # 更新项目时间
    project.updated_at = datetime.now(timezone.utc)
    db.commit()

    return {"filename": filename, "status": "saved"}


# -- 构建操作 ----------------------------------------------------------------


@router.post("/{project_id}/build", response_model=dict)
def trigger_build(project_id: str, db: Session = Depends(get_db)):
    """触发 Docker 镜像构建。构建进度通过 WebSocket 实时推送。"""
    project = db.query(ProjectModel).filter(ProjectModel.id == project_id).first()
    if not project:
        raise HTTPException(status_code=404, detail="项目不存在")

    if project.status == "building":
        raise HTTPException(status_code=409, detail="项目正在构建中")

    # 检查 Dockerfile
    dockerfile_path = _project_dir(project_id) / "Dockerfile"
    if not dockerfile_path.exists():
        raise HTTPException(status_code=400, detail="Dockerfile 不存在")
    if not dockerfile_path.read_text(encoding="utf-8").strip():
        raise HTTPException(status_code=400, detail="Dockerfile 为空")

    # 如果已有构建任务，先取消
    existing_task = _build_tasks.get(project_id)
    if existing_task and not existing_task.done():
        existing_task.cancel()

    # 启动后台构建
    loop = asyncio.get_event_loop()
    task = loop.run_in_executor(None, _run_build_sync, project_id, loop)
    _build_tasks[project_id] = task  # type: ignore[assignment]

    build_id = f"build_{uuid.uuid4().hex[:12]}"
    return {
        "buildId": build_id,
        "status": "started",
        "message": "Build triggered successfully",
    }


# -- Compose 操作 ------------------------------------------------------------


def _get_compose_project_name(project_id: str) -> str:
    """生成 docker-compose 项目名。"""
    return f"mp_{project_id}"


@router.post("/{project_id}/up", response_model=dict)
def project_up(project_id: str, db: Session = Depends(get_db)):
    """启动项目容器（docker compose up -d）。"""
    project = db.query(ProjectModel).filter(ProjectModel.id == project_id).first()
    if not project:
        raise HTTPException(status_code=404, detail="项目不存在")

    if project.status == "building":
        raise HTTPException(status_code=409, detail="项目正在构建中")

    compose_file = _project_dir(project_id) / "docker-compose.yaml"
    if not compose_file.exists():
        raise HTTPException(status_code=400, detail="docker-compose.yaml 不存在")
    if not compose_file.read_text(encoding="utf-8").strip():
        raise HTTPException(status_code=400, detail="docker-compose.yaml 为空")

    compose_name = _get_compose_project_name(project_id)

    try:
        result = subprocess.run(
            [
                "docker",
                "compose",
                "-f",
                str(compose_file),
                "-p",
                compose_name,
                "up",
                "-d",
                "--build",
            ],
            capture_output=True,
            text=True,
            timeout=120,
            cwd=str(_project_dir(project_id)),
        )
        if result.returncode != 0:
            raise HTTPException(
                status_code=500,
                detail=f"启动失败: {result.stderr or result.stdout}",
            )
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=500, detail="启动超时（120s）")
    except FileNotFoundError:
        raise HTTPException(
            status_code=500,
            detail="未找到 docker compose 命令，请确保 Docker Compose 已安装",
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"启动失败: {e}")

    # 获取容器 ID 列表
    container_ids: list[str] = []
    try:
        client = get_docker_client()
        containers = client.containers.list(
            all=True,
            filters={"label": f"com.docker.compose.project={compose_name}"},
        )
        container_ids = [c.id for c in containers]
        client.close()
    except Exception:
        pass

    project.status = "running"
    project.updated_at = datetime.now(timezone.utc)
    db.commit()

    return {
        "status": "started",
        "containerIds": container_ids,
        "message": "Containers started successfully",
    }


@router.post("/{project_id}/down", response_model=dict)
def project_down(project_id: str, db: Session = Depends(get_db)):
    """停止项目容器（docker compose down）。"""
    project = db.query(ProjectModel).filter(ProjectModel.id == project_id).first()
    if not project:
        raise HTTPException(status_code=404, detail="项目不存在")

    compose_file = _project_dir(project_id) / "docker-compose.yaml"
    compose_name = _get_compose_project_name(project_id)

    if compose_file.exists():
        try:
            subprocess.run(
                [
                    "docker",
                    "compose",
                    "-f",
                    str(compose_file),
                    "-p",
                    compose_name,
                    "down",
                ],
                capture_output=True,
                text=True,
                timeout=60,
                cwd=str(_project_dir(project_id)),
            )
        except Exception:
            pass

    project.status = "idle"
    project.updated_at = datetime.now(timezone.utc)
    db.commit()

    return {
        "status": "stopped",
        "message": "Containers stopped successfully",
    }
