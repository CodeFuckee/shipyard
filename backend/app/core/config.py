import os


# --- Security & Config ---
API_KEY_NAME = "X-API-Key"
ADMIN_USER_HEADER = "X-Admin-User"
ADMIN_PASS_HEADER = "X-Admin-Pass"
ADMIN_USER = os.getenv("ADMIN_USER", "admin")  # Username to access Web UI
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "password")  # Password to access Web UI
IGNORED_EVENTS = set(
    os.getenv("IGNORED_EVENTS", "exec_create,exec_start,exec_die").split(",")
)

# --- System Monitoring ---
HOST_FILESYSTEM_ROOT = os.getenv("HOST_FILESYSTEM_ROOT", "/hostfs")

# --- Docker Engine API 代理 ---
DOCKER_SOCKET_PATH = os.getenv("DOCKER_SOCKET_PATH", "/var/run/docker.sock")
DOCKER_ENGINE_API_ENABLED = (
    os.getenv("DOCKER_ENGINE_API_ENABLED", "true").lower() == "true"
)


# --- 头像上传 ---
import pathlib

AVATAR_UPLOAD_DIR = os.getenv(
    "AVATAR_UPLOAD_DIR",
    str(pathlib.Path(__file__).resolve().parent.parent.parent / "static" / "avatars"),
)
MAX_AVATAR_SIZE = int(os.getenv("MAX_AVATAR_SIZE", str(2 * 1024 * 1024)))  # 默认 2MB
ALLOWED_AVATAR_TYPES = {"image/png", "image/jpeg", "image/gif", "image/webp"}

# --- 邮件（SMTP）---
SMTP_HOST = os.getenv("SMTP_HOST", "")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USERNAME = os.getenv("SMTP_USERNAME", "")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "")
SMTP_FROM_EMAIL = os.getenv("SMTP_FROM_EMAIL", "")
SMTP_FROM_NAME = os.getenv("SMTP_FROM_NAME", "Mobile Portainer")
SMTP_USE_SSL = os.getenv("SMTP_USE_SSL", "false").lower() == "true"
SMTP_USE_STARTTLS = os.getenv("SMTP_USE_STARTTLS", "true").lower() == "true"
SMTP_TIMEOUT = int(os.getenv("SMTP_TIMEOUT", "10"))

# --- 项目（Projects）---
PROJECTS_DIR = os.getenv(
    "PROJECTS_DIR",
    str(pathlib.Path(__file__).resolve().parent.parent.parent / "data" / "projects"),
)

# --- 字体缓存（Google Fonts 代理）---
# 前端 Service Worker 将 fonts.gstatic.com 请求改写为 /fonts/{path}，
# 本目录持久化缓存的字体文件（跟随 ./data volume，容器重建不丢）。
FONTS_CACHE_DIR = os.getenv(
    "FONTS_CACHE_DIR",
    str(pathlib.Path(__file__).resolve().parent.parent.parent / "data" / "fonts"),
)

# --- MCP OAuth 认证 ---
MCP_AUTH_ENABLED = os.getenv("MCP_AUTH_ENABLED", "true").lower() == "true"
PUBLIC_BASE_URL = os.getenv("PUBLIC_BASE_URL", "http://127.0.0.1:8000")

# --- Hermes 接入（其他设备上部署的 OpenAI 兼容实例）---
HERMES_BASE_URL = os.getenv("HERMES_BASE_URL", "")  # 实例地址（如 https://hermes.example.com/v1），空 = 未启用
HERMES_API_KEY = os.getenv("HERMES_API_KEY", "")  # 访问密钥（可选，多数自部署实例不需要）
HERMES_MODEL = os.getenv("HERMES_MODEL", "")  # 默认模型名（可选，留空由服务端默认）

# --- 镜像拉取 Agent ---
# 国内镜像源列表（逗号分隔），覆盖默认兜底列表（见 app/agent/mirror_sources.py）
AGENT_MIRROR_PREFIXES = os.getenv("AGENT_MIRROR_PREFIXES", "")
# agent 单轮对话最大工具迭代次数
AGENT_MAX_ITERATIONS = int(os.getenv("AGENT_MAX_ITERATIONS", "10"))
# 单次镜像拉取超时（秒）
AGENT_PULL_TIMEOUT = int(os.getenv("AGENT_PULL_TIMEOUT", "600"))

# --- 备份与恢复 ---
BACKUP_DIR = os.getenv(
    "BACKUP_DIR",
    str(pathlib.Path(__file__).resolve().parent.parent.parent / "data" / "backups"),
)
BACKUP_CRON = os.getenv("BACKUP_CRON", "")  # 定时备份 cron 表达式，空 = 不启用
BACKUP_KEEP_DAYS = int(os.getenv("BACKUP_KEEP_DAYS", "30"))  # 自动清理保留天数
# 定时备份调度配置持久化文件（Web UI 修改后保存于此，优先级高于环境变量）
BACKUP_SCHEDULE_FILE = os.getenv(
    "BACKUP_SCHEDULE_FILE",
    str(pathlib.Path(__file__).resolve().parent.parent.parent / "data" / "backup_schedule.json"),
)
