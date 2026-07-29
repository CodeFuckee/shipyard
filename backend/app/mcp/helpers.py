"""
MCP Server 辅助函数。

提供与 FastAPI 无关的基础设施封装，使 MCP 工具函数可以独立于 Web 框架运行。
主要包括三类功能：

1. Docker 客户端封装 — 连接 Docker 守护进程，错误处理
2. 数据库会话管理 — 上下文管理器模式的数据库访问
3. API Key 认证 — 多层次 API Key 验证策略

=== 设计原则 ===

这些函数的共同特点是「与 FastAPI 无关」：
- get_docker_client_safe() 抛出 RuntimeError 而非 HTTPException
- get_db_session() 使用上下文管理器而非 Depends() 依赖注入
- check_api_key() 直接操作数据库，不依赖 Request 对象

这使得 MCP Server 可以在 stdio 模式下独立运行（不需要运行中的 FastAPI 应用）。
"""

import os
from contextlib import contextmanager

import docker
from sqlalchemy.orm import Session

from app.db.database import SessionLocal
from app.db.models import APIKeyModel

# ---- 模块级常量 ----
# 从环境变量读取 API Key，用于 MCP 客户端认证
# 此变量在模块加载时读取一次，之后不再变化（如需动态更新需重启进程）
_MCP_API_KEY = os.environ.get("MOBILE_PORTAINER_API_KEY")


def get_docker_client_safe() -> docker.DockerClient:
    """返回 Docker 客户端实例，连接失败时抛出 RuntimeError。

    与 app.core.utils.get_docker_client 的核心区别：
    - 本函数抛出 RuntimeError，适用于 MCP 和命令行上下文
    - get_docker_client 抛出 HTTPException，仅适用于 FastAPI 请求上下文

    连接策略：
    - 使用 docker.from_env() 自动检测 Docker 连接配置
    - 支持 DOCKER_HOST 环境变量、Unix socket、TLS 配置等
    - 如果 Docker socket 不可达（权限不足、未安装 Docker 等），抛出异常

    返回:
        docker.DockerClient: 已连接的 Docker 客户端实例

    异常:
        RuntimeError: 无法连接到 Docker 守护进程时抛出，
                      包含具体错误原因
    """
    try:
        return docker.from_env()
    except Exception as e:
        raise RuntimeError(f"无法连接到 Docker 守护进程：{e}")


@contextmanager
def get_db_session():
    """数据库会话上下文管理器。

    替代 FastAPI 的 Depends(get_db) 依赖注入模式。
    在 MCP 工具函数中需要直接访问数据库时使用，
    确保会话在使用完毕后正确关闭。

    SQLAlchemy Session 生命周期：
    1. 创建 Session 实例（从连接池获取连接）
    2. yield 给调用方使用
    3. finally 块中关闭 Session（归还连接到连接池）

    用法:
        with get_db_session() as db:
            # 查询 API Key
            keys = db.query(APIKeyModel).all()
            # 或执行任意 SQLAlchemy 操作
            db.execute(...)

    注意:
        - 不要跨线程共享同一个 session
        - session 在 with 块结束后自动关闭，不要在外部使用
        - 如需事务控制，在 with 块内调用 db.commit() / db.rollback()
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def check_api_key(api_key: str | None = None) -> bool:
    """验证 API Key 是否被授权访问 MCP 服务。

    采用三级回退验证策略，从最安全到最宽松依次尝试：

    第 1 级 — 环境变量模式（最安全）：
        如果设置了 MOBILE_PORTAINER_API_KEY 环境变量，
        则传入的 api_key 必须与之精确匹配。
        适用于只有一个可信客户端的场景（如个人使用）。

    第 2 级 — 数据库验证模式（多用户）：
        如果未设置环境变量，但传入了 api_key，
        则在 SQLite 数据库的 api_keys 表中查找匹配的 key。
        适用于多用户、多 API Key 的管理场景。

    第 3 级 — 无认证模式（最宽松）：
        如果既未设置环境变量，也未传入 api_key，
        则放行所有请求。适用于内网环境或开发调试。

    参数:
        api_key: 待验证的 API Key 字符串，可以为 None

    返回:
        bool: True 表示认证通过，False 表示认证失败

    示例:
        # 环境变量验证
        check_api_key("my-secret-key")  # 返回 True（如果环境变量匹配）

        # 数据库验证
        check_api_key("sk-abc123...")  # 在数据库中查找

        # 无认证
        check_api_key(None)  # 如果没设环境变量，返回 True
    """
    # 第 1 级：环境变量模式 — 必须精确匹配
    if _MCP_API_KEY:
        return api_key == _MCP_API_KEY

    # 第 2 级：数据库验证模式 — 查找 api_keys 表
    if api_key:
        try:
            with get_db_session() as db:
                exists = (
                    db.query(APIKeyModel).filter(APIKeyModel.key == api_key).first()
                )
                return exists is not None
        except Exception:
            # 数据库不可用时返回 False（而非抛出异常，避免暴露内部状态）
            return False

    # 第 3 级：无认证要求 — 允许通过
    return True
