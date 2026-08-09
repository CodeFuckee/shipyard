"""git 仓库克隆功能 —— 供 REST 路由（projects.py）与 MCP 工具（tools.py）共用。

- 支持 http(s):// 与 git@host:path 两种 URL 格式
- 私有仓库认证：URL 内嵌凭据，或环境变量 GIT_USERNAME / GIT_PASSWORD 默认凭据
- 所有对外可见的错误消息都会脱敏 URL 中的密码，避免凭据泄露
"""

from __future__ import annotations

import os
import pathlib
import re
from urllib.parse import quote, urlsplit

import git

# 环境变量默认凭据（用于私有仓库）
GIT_USERNAME_ENV = "GIT_USERNAME"
GIT_PASSWORD_ENV = "GIT_PASSWORD"

# clone 超时（秒），与 docker compose 操作的 120s 超时保持一致
GIT_CLONE_TIMEOUT_DEFAULT = 120

# git URL 长度上限（防御超长输入）
GIT_URL_MAX_LENGTH = 2048

# URL userinfo 部分（user:pass@ 或 user:@），用于密码脱敏
_USERINFO_RE = re.compile(r"(?<=://)[^/@\s]+:[^/@\s]*@")


def sanitize_url(url: str) -> str:
    """脱敏字符串中的 URL 密码（https://user:pass@host → https://user:***@host）。

    用于错误消息，确保密码不会通过异常/响应体泄露。
    """
    return _USERINFO_RE.sub(lambda m: m.group(0).split(":", 1)[0] + ":***@", url)


def extract_repo_name(git_url: str) -> str:
    """从 git URL 提取仓库名（去掉尾部 .git 后缀）。

    https://host/user/myapp.git → myapp
    git@github.com:user/myapp   → myapp

    异常:
        ValueError: URL 为空/格式非法/无法提取仓库名时抛出
    """
    url = git_url.strip()
    if not url:
        raise ValueError("git URL 不能为空")
    if url.startswith("-"):
        raise ValueError("git URL 不能以 '-' 开头")

    if url.startswith("git@"):
        # SSH 格式: git@host:user/repo.git
        if ":" not in url:
            raise ValueError("无效的 SSH git URL，应为 git@host:path 格式")
        path_part = url.split(":", 1)[1]
    else:
        parts = urlsplit(url)
        if parts.scheme not in ("http", "https"):
            raise ValueError(f"不支持的 git URL 协议: {parts.scheme or '无协议'}")
        path_part = parts.path

    name = path_part.rstrip("/").rsplit("/", 1)[-1]
    if name.endswith(".git"):
        name = name[:-4]
    if not name or name in {".", ".."}:
        raise ValueError("无法从 git URL 提取仓库名")
    return name


def normalize_git_url(git_url: str) -> str:
    """校验 git URL 并注入环境变量默认凭据，返回最终用于 clone 的 URL。

    校验规则:
    - 非空，长度 ≤ 2048
    - 仅接受 http://、https:// 或 git@host:path（git@ 后不能是绝对路径）
    - 不允许以 '-' 开头（防止 git 参数注入，如 --upload-pack=...）

    凭据规则:
    - URL 已内嵌 user:pass@ → 保持原样（优先级高于环境变量）
    - http(s) URL 无内嵌凭据且设置了 GIT_USERNAME → 注入环境凭据（特殊字符百分号编码）
    - SSH 格式无法注入 http 凭据，依赖系统 SSH key

    异常:
        ValueError: URL 非法时抛出
    """
    url = git_url.strip()
    if not url:
        raise ValueError("git URL 不能为空")
    if len(url) > GIT_URL_MAX_LENGTH:
        raise ValueError(f"git URL 长度不能超过 {GIT_URL_MAX_LENGTH} 字符")
    if url.startswith("-"):
        raise ValueError("git URL 不能以 '-' 开头")

    if url.startswith("git@"):
        # SSH 格式：校验 host:path 结构，不注入 http 凭据
        rest = url[len("git@") :]
        if ":" not in rest:
            raise ValueError("无效的 SSH git URL，应为 git@host:path 格式")
        host, path = rest.split(":", 1)
        if not host:
            raise ValueError("无效的 SSH git URL：缺少主机名")
        if not path:
            raise ValueError("无效的 SSH git URL：缺少仓库路径")
        if path.startswith("/"):
            raise ValueError("无效的 SSH git URL：路径不能以 '/' 开头")
        return url

    parts = urlsplit(url)
    if parts.scheme not in ("http", "https"):
        raise ValueError(f"不支持的 git URL 协议: {parts.scheme or '无协议'}")
    if not parts.hostname:
        raise ValueError("git URL 缺少主机名")

    # 注入环境变量默认凭据（仅当 URL 未内嵌凭据）
    if parts.username is None:
        username = os.getenv(GIT_USERNAME_ENV, "")
        if username:
            password = os.getenv(GIT_PASSWORD_ENV, "")
            creds = f"{quote(username, safe='')}:{quote(password, safe='')}@"
            query = f"?{parts.query}" if parts.query else ""
            return (
                f"{parts.scheme}://{creds}{parts.netloc}"
                f"{parts.path or '/'}{query}"
            )
    return url


def clone_repo(
    git_url: str, dest: pathlib.Path, timeout: int = GIT_CLONE_TIMEOUT_DEFAULT
) -> None:
    """克隆 git 仓库到 dest 目录（保留 .git，便于后续 pull 更新）。

    使用 GitPython 的 kill_after_timeout 控制超时。失败时抛出
    RuntimeError，错误消息已脱敏（不包含 URL 中的密码）。

    异常:
        RuntimeError: clone 失败或超时时抛出
    """
    try:
        git.Repo.clone_from(
            git_url,
            str(dest),
            kill_after_timeout=timeout,
        )
    except git.exc.GitCommandError as exc:
        raise RuntimeError(f"git clone 失败: {sanitize_url(str(exc))}") from exc
    except Exception as exc:
        raise RuntimeError(f"git clone 失败: {sanitize_url(str(exc))}") from exc
