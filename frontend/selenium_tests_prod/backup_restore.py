"""生产环境写操作测试的备份/恢复保护工具。

背景：test_prod_connect.py 等写操作测试会在生产环境上留下状态
（目标服务器注册 public client / 签发 apikey、源服务器服务器列表新增等），
为满足"测试前备份、测试后恢复"的要求，本模块通过后端自带的备份/恢复
API（POST /backups、POST /backups/{filename}/restore）实现：

    测试前 create_backup() → 测试结束后 restore_backup() + wait_backend_alive()

后端备份内容为自身 SQLite 数据库（keys.db，含 api_keys / connect_clients /
server_list 等全部业务表），恢复会覆盖数据库并触发服务重启
（Docker restart policy 自动拉起），因此恢复后需等待服务重新可用。

认证：与后端 get_api_key 对齐，支持双通道（二选一即可）：
- X-API-Key：api_keys 表中已有的 key，经 TEST_API_KEY 环境变量注入，
  支持按主机覆盖 TEST_API_KEY_<host>（host 中 `.` 替换为 `_`）
- X-Admin-User + X-Admin-Pass：管理端凭据回退，复用登录凭据
  TEST_USERNAME / TEST_PASSWORD（支持按主机覆盖 TEST_USERNAME_<host> /
  TEST_PASSWORD_<host>，与 config.per_host_creds 的约定一致）

与生产环境相关的行为由 test_prod_connect.py 端到端覆盖，
本模块的纯逻辑由 tests/test_backup_restore_util.py 离线覆盖。
"""

import json
import os
import re
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from urllib.parse import urlparse

# 后端备份文件名规范（与 backend/app/services/backup_service.py 保持一致）：
# backup_YYYYMMDD_HHMMSS[._pre_restore].tar.gz.enc
_BACKUP_NAME_RE = re.compile(r"^backup_\d{8}_\d{6}(?:_pre_restore)?\.tar\.gz\.enc$")

_DEFAULT_TIMEOUT = 30


@dataclass
class AuthTarget:
    """一个生产环境及其可用认证方式（API key 或 Admin 凭据，任一可用即可）。"""

    url: str
    api_key: str = ""
    admin_user: str = ""
    admin_pass: str = ""

    @property
    def enabled(self) -> bool:
        """任一认证通道可用即视为可保护。"""
        return bool(self.api_key or (self.admin_user and self.admin_pass))


def _host_key(url: str) -> str:
    """URL 主机名转 per-host 变量的键（. 替换为 _，端口不参与）。"""
    return (urlparse(url).hostname or "").replace(".", "_")


def per_host_api_key(url: str) -> str:
    """按主机名解析 API key：TEST_API_KEY_<host> 优先，回退 TEST_API_KEY。

    全部缺失返回空串。
    """
    host = _host_key(url)
    return os.environ.get(f"TEST_API_KEY_{host}", "") or os.environ.get("TEST_API_KEY", "")


def per_host_admin_creds(url: str) -> tuple[str, str]:
    """按主机名解析 Admin 凭据：TEST_USERNAME_<host>/TEST_PASSWORD_<host> 优先。

    回退全局 TEST_USERNAME / TEST_PASSWORD（与 config.per_host_creds 一致）。
    全部缺失返回 ("", "")。
    """
    host = _host_key(url)
    user = os.environ.get(f"TEST_USERNAME_{host}", "") or os.environ.get("TEST_USERNAME", "")
    pwd = os.environ.get(f"TEST_PASSWORD_{host}", "") or os.environ.get("TEST_PASSWORD", "")
    return user, pwd


def backup_restore_targets(urls: list[str]) -> list[AuthTarget]:
    """解析每个环境的可用认证，返回启用保护的目标列表。

    API key 或 Admin 凭据任一可用即启用保护；两者都缺失的环境被剔除，
    调用方（conftest fixture）据此决定保护范围（无任何目标时不应裸跑
    写操作测试）。
    """
    targets = []
    for url in urls:
        target = AuthTarget(
            url=url,
            api_key=per_host_api_key(url),
        )
        target.admin_user, target.admin_pass = per_host_admin_creds(url)
        if target.enabled:
            targets.append(target)
    return targets


def _is_backup_name(filename: str) -> bool:
    """校验备份文件名是否符合后端命名规范（防路径穿越/误恢复非备份文件）。"""
    return bool(_BACKUP_NAME_RE.match(filename or ""))


def _request_json(
    method: str,
    url: str,
    target: AuthTarget | None = None,
    data: dict | None = None,
    timeout: int = _DEFAULT_TIMEOUT,
) -> tuple[int, dict]:
    """发起 JSON 请求，返回 (HTTP 状态码, 解析后的响应体)。

    认证头与后端 get_api_key 对齐：X-API-Key 或
    X-Admin-User + X-Admin-Pass（后端支持 Admin 凭据回退，见
    backend/app/core/security.py 的 get_api_key）。

    与 conftest._check_reachability 对齐的两个关键点：
    - 强制直连（ProxyHandler({})）：不继承系统/环境代理
    - HTTPS 跳过证书验证：生产环境 https 可能证书过期/自签
      （浏览器测试已通过 --ignore-certificate-errors 忽略证书）
    非 2xx 状态码抛 RuntimeError（带后端 detail 信息），连接失败同理。
    """
    headers = {}
    if target:
        if target.api_key:
            headers["X-API-Key"] = target.api_key
        elif target.admin_user and target.admin_pass:
            headers["X-Admin-User"] = target.admin_user
            headers["X-Admin-Pass"] = target.admin_pass
    body = None
    if data is not None:
        body = json.dumps(data).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        urllib.request.HTTPSHandler(context=__import__("ssl")._create_unverified_context()),
    )
    try:
        with opener.open(req, timeout=timeout) as resp:
            status = resp.status
            raw = resp.read()
    except urllib.error.HTTPError as e:
        # 后端错误响应：尽量提取 detail 便于排查
        detail = ""
        try:
            detail = json.loads(e.read().decode("utf-8", "replace")).get("detail", "")
        except Exception:
            pass
        raise RuntimeError(f"{e.code} {e.reason}: {detail}") from e
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        raise RuntimeError(f"请求失败: {e}") from e
    if status >= 400:
        raise RuntimeError(f"HTTP {status}")
    parsed = {}
    if raw:
        try:
            parsed = json.loads(raw.decode("utf-8", "replace"))
        except json.JSONDecodeError:
            parsed = {}
    return status, parsed


def create_backup(target: AuthTarget, timeout: int = _DEFAULT_TIMEOUT) -> str:
    """在目标生产环境创建一次备份，返回备份文件名（供恢复时使用）。"""
    url = f"{target.url.rstrip('/')}/backups"
    _, body = _request_json("POST", url, target=target, timeout=timeout)
    filename = body.get("filename") if isinstance(body, dict) else None
    if not filename:
        raise RuntimeError(f"创建备份响应缺少 filename 字段: {body}")
    return filename


def restore_backup(
    target: AuthTarget, filename: str, timeout: int = _DEFAULT_TIMEOUT
) -> None:
    """从指定备份恢复目标环境（覆盖当前数据，需 confirm=true 才执行）。

    恢复后服务会重启，调用方需用 wait_backend_alive 等待重新可用。
    """
    if not _is_backup_name(filename):
        raise ValueError(f"非法备份文件名: {filename}")
    url = (
        f"{target.url.rstrip('/')}/backups/{filename}/restore?confirm=true"
    )
    _request_json("POST", url, target=target, timeout=timeout)


def _backend_reachable(base_url: str, timeout: int = 5) -> bool:
    """探测后端服务是否在响应（恢复触发重启后的可用性检查）。

    探测 FastAPI 端点 /docs（而不是 /——生产部署 nginx 前置，恢复期间
    nginx 静态页始终 200，探测 / 会误判"已恢复"）：
    - 任何应用层 HTTP 响应（200/401/404 等）视为服务已恢复
    - 502/503/504（nginx 上游错误，uvicorn 未就绪）视为未恢复
    - 连接失败/超时视为未恢复
    """
    url = f"{base_url.rstrip('/')}/docs"
    req = urllib.request.Request(url, method="GET")
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        urllib.request.HTTPSHandler(context=__import__("ssl")._create_unverified_context()),
    )
    try:
        opener.open(req, timeout=timeout)
        return True
    except urllib.error.HTTPError as e:
        if e.code in (502, 503, 504):
            return False  # nginx 上游错误：uvicorn 尚未就绪
        return True  # 应用层在响应（4xx/5xx 也说明已恢复）
    except (urllib.error.URLError, TimeoutError, OSError):
        return False


def wait_backend_alive(
    base_url: str, timeout: float = 120.0, interval: float = 2.0
) -> bool:
    """等待后端服务在恢复重启后重新可用，超时返回 False（不抛异常）。"""
    if timeout <= 0:
        return False
    deadline = time.monotonic() + timeout
    while True:
        if _backend_reachable(base_url):
            return True
        if time.monotonic() >= deadline:
            return False
        time.sleep(min(interval, max(0.1, deadline - time.monotonic())))
