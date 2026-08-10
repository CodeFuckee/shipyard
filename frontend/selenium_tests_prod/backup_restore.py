"""生产环境写操作测试的备份/恢复保护工具。

背景：test_prod_connect.py 等写操作测试会在生产环境上留下状态
（目标服务器注册 public client / 签发 apikey、源服务器服务器列表新增等），
为满足"测试前备份、测试后恢复"的要求，本模块通过后端自带的备份/恢复
API（POST /backups、POST /backups/{filename}/restore）实现：

    测试前 create_backup() → 测试结束后 restore_backup() + wait_backend_alive()

后端备份内容为自身 SQLite 数据库（keys.db，含 api_keys / connect_clients /
server_list 等全部业务表），恢复会覆盖数据库并触发服务重启
（Docker restart policy 自动拉起），因此恢复后需等待服务重新可用。

认证：与 admin 管理端点一致，使用 X-API-Key 请求头。key 通过
TEST_API_KEY 环境变量注入，支持按主机覆盖 TEST_API_KEY_<host>
（host 中 `.` 替换为 `_`，与登录凭据 per_host_creds 的约定一致）。

与生产环境相关的行为由 test_prod_connect.py 端到端覆盖，
本模块的纯逻辑由 tests/test_backup_restore_util.py 离线覆盖。
"""

import json
import os
import re
import time
import urllib.error
import urllib.request
from urllib.parse import urlparse

# 后端备份文件名规范（与 backend/app/services/backup_service.py 保持一致）：
# backup_YYYYMMDD_HHMMSS[._pre_restore].tar.gz.enc
_BACKUP_NAME_RE = re.compile(r"^backup_\d{8}_\d{6}(?:_pre_restore)?\.tar\.gz\.enc$")

_DEFAULT_TIMEOUT = 30


def per_host_api_key(url: str) -> str:
    """按主机名解析 API key：TEST_API_KEY_<host> 优先，回退 TEST_API_KEY。

    host 中 `.` 替换为 `_`（与 config.per_host_creds 的约定一致），
    端口不参与匹配。全部缺失返回空串。
    """
    host = (urlparse(url).hostname or "").replace(".", "_")
    return os.environ.get(f"TEST_API_KEY_{host}", "") or os.environ.get("TEST_API_KEY", "")


def backup_restore_targets(urls: list[str]) -> list[tuple[str, str]]:
    """过滤出需要备份保护的环境，返回 [(url, api_key), ...]。

    未配置 API key 的环境无法调用备份/恢复 API，直接剔除；
    调用方（conftest fixture）据此决定保护范围。
    """
    targets = []
    for url in urls:
        key = per_host_api_key(url)
        if key:
            targets.append((url, key))
    return targets


def _is_backup_name(filename: str) -> bool:
    """校验备份文件名是否符合后端命名规范（防路径穿越/误恢复非备份文件）。"""
    return bool(_BACKUP_NAME_RE.match(filename or ""))


def _request_json(
    method: str,
    url: str,
    api_key: str = "",
    data: dict | None = None,
    timeout: int = _DEFAULT_TIMEOUT,
) -> tuple[int, dict]:
    """发起 JSON 请求，返回 (HTTP 状态码, 解析后的响应体)。

    与 conftest._check_reachability 对齐的两个关键点：
    - 强制直连（ProxyHandler({})）：不继承系统/环境代理
    - HTTPS 跳过证书验证：生产环境 https 可能证书过期/自签
      （浏览器测试已通过 --ignore-certificate-errors 忽略证书）
    非 2xx 状态码抛 RuntimeError（带后端 detail 信息），连接失败同理。
    """
    headers = {}
    if api_key:
        headers["X-API-Key"] = api_key
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


def create_backup(base_url: str, api_key: str, timeout: int = _DEFAULT_TIMEOUT) -> str:
    """在目标生产环境创建一次备份，返回备份文件名（供恢复时使用）。"""
    url = f"{base_url.rstrip('/')}/backups"
    _, body = _request_json("POST", url, api_key=api_key, timeout=timeout)
    filename = body.get("filename") if isinstance(body, dict) else None
    if not filename:
        raise RuntimeError(f"创建备份响应缺少 filename 字段: {body}")
    return filename


def restore_backup(
    base_url: str, api_key: str, filename: str, timeout: int = _DEFAULT_TIMEOUT
) -> None:
    """从指定备份恢复目标环境（覆盖当前数据，需 confirm=true 才执行）。

    恢复后服务会重启，调用方需用 wait_backend_alive 等待重新可用。
    """
    if not _is_backup_name(filename):
        raise ValueError(f"非法备份文件名: {filename}")
    url = (
        f"{base_url.rstrip('/')}/backups/{filename}/restore?confirm=true"
    )
    _request_json("POST", url, api_key=api_key, timeout=timeout)


def _backend_reachable(base_url: str, timeout: int = 5) -> bool:
    """探测后端服务是否在响应（恢复触发重启后的可用性检查）。

    任何 HTTP 响应（包括 401/404 等）都视为服务已恢复；
    仅连接失败/超时视为未恢复。
    """
    url = f"{base_url.rstrip('/')}/"
    req = urllib.request.Request(url, method="GET")
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        urllib.request.HTTPSHandler(context=__import__("ssl")._create_unverified_context()),
    )
    try:
        opener.open(req, timeout=timeout)
        return True
    except urllib.error.HTTPError:
        return True  # 服务在响应（4xx/5xx 也说明已恢复）
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
