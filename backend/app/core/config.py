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

# --- MCP OAuth 认证 ---
MCP_AUTH_ENABLED = os.getenv("MCP_AUTH_ENABLED", "true").lower() == "true"
PUBLIC_BASE_URL = os.getenv("PUBLIC_BASE_URL", "http://127.0.0.1:8000")
