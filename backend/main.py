from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import asyncio
import threading
from contextlib import asynccontextmanager
from app.db.database import engine, Base
from app.services.docker_monitor import docker_event_listener

# Import Routers
from app.routers import (
    containers,
    images,
    networks,
    volumes,
    system,
    admin,
    websockets,
    # web_ui,  # 前端已迁移至独立 Flutter Web 服务
    stacks,
    docker_proxy,
    projects,
    connect,
    fonts,
    backups,
    ai_providers,
    hermes,
    agent,
)
from app.core.config import BACKUP_CRON, DOCKER_ENGINE_API_ENABLED
from app.mcp.http_server import (
    mcp_http_app,
    mcp_session_manager,
    mcp_oauth_routes,
    mcp_protected_resource_routes,
)

# Initialize Database
Base.metadata.create_all(bind=engine)


def _migrate_lightweight_schema():
    """轻量迁移：create_all 不会为已有表补充新列，这里为老库补列。

    - ai_providers.is_default（issue #21 第四轮，默认供应商标记，0/1）
    """
    from sqlalchemy import inspect, text

    inspector = inspect(engine)
    if "ai_providers" not in inspector.get_table_names():
        return
    columns = {c["name"] for c in inspector.get_columns("ai_providers")}
    if "is_default" not in columns:
        with engine.begin() as conn:
            conn.execute(
                text("ALTER TABLE ai_providers ADD COLUMN is_default INTEGER DEFAULT 0")
            )


_migrate_lightweight_schema()

DESCRIPTION = """
Mobile Portainer 是一款轻量级的 Docker 管理 API，支持容器、镜像、网络、卷、堆栈的管理。

## 认证方式

所有 API 端点（除文档页面和 WebSocket）都需要通过以下任一方式认证：

| 方式 | 说明 |
|------|------|
| **X-API-Key** | 在请求头中传入 `X-API-Key: <your_api_key>` |
| **Authorization: Bearer** | 在请求头中传入 `Authorization: Bearer <your_api_key>` |
| **Admin 凭据** | 在请求头中传入 `X-Admin-User` 和 `X-Admin-Pass` |

> 💡 点击右上角 **Authorize** 🔒 按钮，输入你的 API Key 即可在 Swagger UI 中测试所有端点。

## 功能模块

- **Containers** — 容器生命周期管理（创建、启动、停止、日志查看、终端交互）
- **Images** — 镜像拉取、删除、搜索
- **Volumes** — 数据卷管理
- **Networks** — 网络管理
- **Stacks** — Docker Compose 堆栈管理
- **System** — 系统信息、资源使用、可用端口检测
- **Admin** — API Key 管理、管理员凭据、集群配置
- **Docker Engine API** — 原生 Docker API 透传代理
- **WebSocket** — 容器状态实时推送
- **MCP** — MCP Streamable HTTP 端点，供 AI 助手管理 Docker 资源
"""

TAGS_METADATA = [
    {
        "name": "containers",
        "description": "容器管理 — 创建、启动、停止、删除容器，查看日志和终端",
    },
    {"name": "images", "description": "镜像管理 — 拉取、删除、搜索 Docker 镜像"},
    {"name": "volumes", "description": "数据卷管理 — 创建、删除、查看数据卷"},
    {"name": "networks", "description": "网络管理 — 创建、删除、查看 Docker 网络"},
    {"name": "stacks", "description": "堆栈管理 — Docker Compose 项目容器管理"},
    {
        "name": "projects",
        "description": "项目管理 — Dockerfile 编辑、镜像构建、compose 启停",
    },
    {
        "name": "system",
        "description": "系统信息 — 主机资源、Docker 信息、可用端口、Git 更新",
    },
    {
        "name": "admin",
        "description": "管理功能 — API Key 管理、管理员密码、集群节点、邮件服务",
    },
    {"name": "docker-engine-api", "description": "Docker Engine API 透传代理"},
    {"name": "websockets", "description": "WebSocket — 容器状态实时推送"},
]


@asynccontextmanager
async def lifespan(app: FastAPI):
    """应用生命周期管理：启动 Docker 事件监听、定时备份调度和 MCP 会话管理器。"""
    # Startup
    loop = asyncio.get_event_loop()
    threading.Thread(target=docker_event_listener, args=(loop,), daemon=True).start()

    # 启动定时备份调度线程（BACKUP_CRON 配置了才启动）
    if BACKUP_CRON:
        from app.services.backup_scheduler import start_backup_scheduler

        threading.Thread(target=start_backup_scheduler, daemon=True).start()

    # 加载 Hermes 接入配置（前端设置页保存的数据库值优先于环境变量）
    from app.db.database import SessionLocal
    from app.services import hermes_client, hermes_config

    # ⚠️ 不能用 `with SessionLocal() as db:`：Session 上下文管理器协议
    # 是 SQLAlchemy 1.4 才引入的，pip 构建时网络抖动可能回溯装到 1.3.x
    # 导致 TypeError 启动崩溃（流水线 #535 实测），用 try/finally 兼容
    db = SessionLocal()
    try:
        config = hermes_config.load(db)
        hermes_client.set_runtime_config(
            base_url=config["base_url"],
            api_key=config["api_key"],
            model=config["model"],
        )
    finally:
        db.close()

    # 启动 MCP session manager
    async with mcp_session_manager.run():
        yield

    # Shutdown
    from app.core.docker_socket import close_docker_http_client

    await close_docker_http_client()


app = FastAPI(
    title="Mobile Portainer API",
    description=DESCRIPTION,
    version="1.0.0",
    openapi_tags=TAGS_METADATA,
    lifespan=lifespan,
    swagger_ui_parameters={
        "persistAuthorization": True,  # 刷新页面后保留认证信息
        "displayRequestDuration": True,  # 显示请求耗时
        "filter": True,  # 启用标签过滤
        "tryItOutEnabled": True,  # 默认启用 "Try it out"
        "deepLinking": True,  # 支持深度链接到具体操作
    },
)

# Add CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API Routers first (takes priority)
app.include_router(containers.router)
app.include_router(images.router)
app.include_router(networks.router)
app.include_router(volumes.router)
app.include_router(stacks.router)
app.include_router(system.router)
app.include_router(admin.router)
app.include_router(websockets.router)
app.include_router(projects.router)
app.include_router(projects.ws_router)

# 跨实例服务器授权添加（/connect 流程，交互式授权页 + PKCE）
app.include_router(connect.router)
app.include_router(fonts.router)
app.include_router(backups.router)
app.include_router(ai_providers.router)
app.include_router(hermes.router)
app.include_router(agent.router)

# Docker Engine API 代理（在 API 路由之后、Web UI 之前）
if DOCKER_ENGINE_API_ENABLED:
    app.include_router(docker_proxy.router)

# 挂载静态文件目录（用于头像等上传文件访问）
app.mount("/static", StaticFiles(directory="static"), name="static")

# 注册 OAuth 路由（必须在根路径，先于 MCP mount）
# MCP 客户端按 RFC 8414 规范在服务根路径发现 OAuth 端点
for route in mcp_oauth_routes + mcp_protected_resource_routes:
    app.router.routes.append(route)

# 挂载 MCP Streamable HTTP 端点（MCP 协议端点，需要 Bearer token 认证）
app.mount("/mcp", mcp_http_app)


# Web UI 前端已迁移至独立 Flutter Web 服务（nginx 容器）
# app.include_router(web_ui.router)
