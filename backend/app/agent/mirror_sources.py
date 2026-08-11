"""镜像源管理 — Agent 工具使用的国内 Docker 镜像源列表。

来源优先级：环境变量 AGENT_MIRROR_PREFIXES（逗号分隔）> 默认兜底列表。
默认列表与 backend/skills/docker-mirror-pull/SKILL.md 中的已知镜像源保持一致。
"""

from app.core.config import AGENT_MIRROR_PREFIXES

# 默认兜底镜像源（镜像源地址经常变化，部署时可用 AGENT_MIRROR_PREFIXES 覆盖）
DEFAULT_MIRROR_PREFIXES = [
    "docker.1ms.run",
    "docker.m.daocloud.io",
    "dockerproxy.com",
    "dockerhub.icu",
    "hub.rat.dev",
    "docker.hpcloud.cloud",
    "docker.registry.cyou",
]


def get_mirror_prefixes() -> list[str]:
    """生效的镜像源前缀列表：环境变量优先，否则返回默认兜底列表。"""
    configured = [p.strip() for p in AGENT_MIRROR_PREFIXES.split(",") if p.strip()]
    return configured or list(DEFAULT_MIRROR_PREFIXES)
