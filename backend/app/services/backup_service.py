"""备份与恢复服务 —— Shipyard 自身数据（SQLite 数据库 keys.db）。

备份流程：
    1. sqlite3 backup() API 在线导出数据库一致副本（兼容 WAL，不打断写入）
    2. tar.gz 打包：keys.db + meta.json（时间戳、表数量等元信息）
    3. 用 SECRET_KEY 派生密钥整体加密（app.core.backup_crypto）
    4. 落到备份目录（BACKUP_DIR，默认 backend/data/backups/）

恢复流程（覆盖现有数据）：
    1. 必须显式 confirm=True（危险操作防误触）
    2. 解密 → 校验 tar.gz 完整性 → 校验内部 keys.db 是合法 SQLite（PRAGMA integrity_check）
    3. 恢复前自动生成 pre_restore 快照（当前库的加密备份，可回退）
    4. 原子替换数据库文件
    5. 触发进程重启（restart_process），由 Docker restart policy 拉起加载新库
       —— 因为 FastAPI 进程持有的 SQLite 连接仍指向旧文件 inode

保留策略：按 BACKUP_KEEP_DAYS 天清理（mtime 超过 keep_days 的删除）；
同时支持手动删除（DELETE /backups/{filename}）。
"""

import io
import json
import os
import re
import shutil
import sqlite3
import tarfile
import tempfile
from datetime import datetime
from pathlib import Path
from typing import List, Optional

from app.core.backup_crypto import decrypt_file, encrypt_file
from app.core.config import BACKUP_DIR

# 备份文件名格式：backup_YYYYMMDD_HHMMSS.tar.gz.enc
_BACKUP_NAME_RE = re.compile(r"^backup_\d{8}_\d{6}(?:_pre_restore)?\.tar\.gz\.enc$")
_TAR_MEMBER_DB = "keys.db"
_TAR_MEMBER_META = "meta.json"


# ---------------------------------------------------------------------------
# 路径解析（测试通过 monkeypatch 覆盖）
# ---------------------------------------------------------------------------

def get_db_path() -> Path:
    """当前数据库文件路径（从 SQLAlchemy 的 URL 解析）。"""
    from app.db.database import SQLALCHEMY_DATABASE_URL

    # sqlite:///./data/keys.db → ./data/keys.db
    url = SQLALCHEMY_DATABASE_URL.replace("sqlite:///", "", 1)
    return Path(url)


def get_backup_dir() -> Path:
    """备份目录（BACKUP_DIR 环境变量可配）。"""
    return Path(BACKUP_DIR)


# ---------------------------------------------------------------------------
# 备份
# ---------------------------------------------------------------------------

def _export_db_copy(db_path: Path, dst_path: Path) -> None:
    """用 sqlite3 backup() API 导出一致副本，避免拷贝时文件被写坏。"""
    src_conn = sqlite3.connect(str(db_path))
    try:
        dst_conn = sqlite3.connect(str(dst_path))
        try:
            src_conn.backup(dst_conn)
        finally:
            dst_conn.close()
    finally:
        src_conn.close()


def _table_count(db_path: Path) -> int:
    """统计库内业务表数量（供 meta.json）。"""
    conn = sqlite3.connect(str(db_path))
    try:
        rows = conn.execute(
            "SELECT count(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        ).fetchone()
        return int(rows[0]) if rows else 0
    finally:
        conn.close()


def _backup_filename(now: datetime, pre_restore: bool = False) -> str:
    suffix = "_pre_restore" if pre_restore else ""
    return f"backup_{now.strftime('%Y%m%d_%H%M%S')}{suffix}.tar.gz.enc"


def _create_backup_file(db_path: Path, backup_dir: Path, pre_restore: bool = False) -> dict:
    """核心备份逻辑：导出库 → tar.gz → 加密。返回备份信息。"""
    if not db_path.exists():
        raise FileNotFoundError(f"数据库文件不存在: {db_path}")

    now = datetime.now()
    filename = _backup_filename(now, pre_restore)
    backup_dir.mkdir(parents=True, exist_ok=True)

    # 1. 在线导出数据库一致副本到临时目录
    with tempfile.TemporaryDirectory(dir=str(backup_dir)) as tmp:
        tmp_path = Path(tmp)
        db_copy = tmp_path / "keys.db"
        _export_db_copy(db_path, db_copy)

        # 2. tar.gz 打包（keys.db + meta.json）
        meta = {
            "app": "shipyard",
            "created_at": now.strftime("%Y%m%d%H%M%S"),
            "table_count": _table_count(db_copy),
            "pre_restore": pre_restore,
        }
        meta_path = tmp_path / "meta.json"
        meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")

        packed = tmp_path / "backup.tar.gz"
        with tarfile.open(packed, mode="w:gz") as tar:
            tar.add(db_copy, arcname=_TAR_MEMBER_DB)
            tar.add(meta_path, arcname=_TAR_MEMBER_META)

        # 3. 加密落盘
        enc_path = backup_dir / filename
        encrypt_file(packed, enc_path)

    return {
        "filename": filename,
        "size": enc_path.stat().st_size,
        "created_at": meta["created_at"],
    }


def create_backup() -> dict:
    """手动/定时创建备份，返回备份信息（filename/size/created_at）。"""
    return _create_backup_file(get_db_path(), get_backup_dir())


# ---------------------------------------------------------------------------
# 列表 / 删除 / 清理
# ---------------------------------------------------------------------------

def _is_backup_name(name: str) -> bool:
    """仅接受符合命名规范的备份文件（防路径穿越 / 误删非备份文件）。"""
    return bool(_BACKUP_NAME_RE.match(name))


def list_backups() -> List[dict]:
    """列出备份目录中的备份文件，按文件名（含时间）倒序。"""
    backup_dir = get_backup_dir()
    if not backup_dir.exists():
        return []
    items = []
    for path in sorted(backup_dir.iterdir(), key=lambda p: p.name, reverse=True):
        if path.is_file() and _is_backup_name(path.name):
            items.append(
                {
                    "filename": path.name,
                    "size": path.stat().st_size,
                    "created_at": path.name[7:21],  # backup_YYYYMMDD_HHMMSS
                }
            )
    return items


def delete_backup(filename: str) -> None:
    """手动删除指定备份文件。文件名不合规范或不存在时抛异常。"""
    if not _is_backup_name(filename):
        raise ValueError(f"非法的备份文件名: {filename!r}")
    path = get_backup_dir() / filename
    if not path.exists():
        raise FileNotFoundError(f"备份不存在: {filename}")
    path.unlink()


def cleanup_old_backups(keep_days: int) -> int:
    """清理超过保留天数的备份，返回删除数量。仅处理规范命名的备份文件。"""
    backup_dir = get_backup_dir()
    if not backup_dir.exists():
        return 0
    deadline = datetime.now().timestamp() - keep_days * 86400
    removed = 0
    for path in backup_dir.iterdir():
        if not (path.is_file() and _is_backup_name(path.name)):
            continue
        if path.stat().st_mtime < deadline:
            path.unlink()
            removed += 1
    return removed


# ---------------------------------------------------------------------------
# 恢复
# ---------------------------------------------------------------------------

def _verify_db_integrity(db_path: Path) -> None:
    """校验数据库文件是合法 SQLite 且无损坏，否则抛异常。"""
    conn = sqlite3.connect(str(db_path))
    try:
        row = conn.execute("PRAGMA integrity_check").fetchone()
        if not row or row[0] != "ok":
            raise ValueError(f"备份内数据库损坏: {row}")
    finally:
        conn.close()


def restart_process() -> None:
    """恢复生效方式：替换数据库后退出进程，由 Docker restart policy 拉起。

    生产部署以 uvicorn --reload 启动（backend/Dockerfile），容器主进程是
    reloader 父进程：其 run() 循环只等待文件变化才重启 worker（uvicorn
    0.52 源码，supervisors/basereload.py），worker 自行退出（os._exit）
    后 reloader 毫无察觉也不会拉起新 worker——实测恢复后 nginx 存活但
    后端永久挂起，直到容器被重建。因此必须终止容器主进程让 Docker
    重启整个容器：

    - 有父进程（--reload 模式：reloader 是容器 PID 1，worker 的 ppid=1）：
      先 SIGKILL 父进程（容器主进程退出 → Docker restart policy 拉起
      全新容器加载新库）
    - 无父进程（ppid=0，worker 即容器主进程，非 --reload 部署）：
      os._exit 直接退出即触发容器重启

    FastAPI 持有的 SQLite 连接指向旧文件 inode，不重启无法加载替换后的库。
    """
    import signal
    import sys

    # 先刷新标准输出，确保日志落盘
    try:
        sys.stdout.flush()
        sys.stderr.flush()
    finally:
        # 终止 reloader 父进程（uvicorn --reload 的容器主进程）；
        # ppid=0 表示自身即容器主进程，跳过（下方 os._exit 兜底）
        try:
            ppid = os.getppid()
            if ppid > 0:
                os.kill(ppid, signal.SIGKILL)
        except (OSError, ValueError):
            pass
        os._exit(1)


def _remove_stale_wal_files(db_path: Path) -> None:
    """删除数据库替换后残留的 WAL/SHM 文件。

    SQLite WAL 模式下运行的老进程持有旧 inode 的 keys.db-wal / keys.db-shm；
    替换主文件后这些残留文件与新库不匹配，新进程打开时可能误回放旧日志
    或报错。恢复时一并清理（老进程即将被重启杀掉，其后续写入成为孤儿，
    无碍；新进程打开干净的主文件）。
    """
    for suffix in ("-wal", "-shm"):
        stale = Path(f"{db_path}{suffix}")
        try:
            if stale.exists():
                stale.unlink()
        except OSError as e:
            print(f"[backup] 清理 {stale.name} 失败（忽略）: {e}")


def restore_backup(filename: str, confirm: bool = False, restart: bool = True) -> dict:
    """从备份恢复数据库（覆盖现有数据），成功后触发进程重启。

    restart=True（默认）时在返回前立即退出进程（由 Docker restart policy
    拉起加载新库）；restart=False 时不退出，由调用方（REST 端点）通过
    BackgroundTask 在响应发送后触发——避免 os._exit 在响应写出前杀掉
    进程导致客户端收到 502/连接重置。

    返回恢复信息（含 pre_restore 快照文件名）。所有校验失败时抛异常，
    原数据库保持不动。
    """
    if not confirm:
        raise ValueError("恢复操作会覆盖现有数据，必须显式 confirm=true 确认")

    if not _is_backup_name(filename):
        raise ValueError(f"非法的备份文件名: {filename!r}")

    backup_dir = get_backup_dir()
    enc_path = backup_dir / filename
    if not enc_path.exists():
        raise FileNotFoundError(f"备份不存在: {filename}")

    db_path = get_db_path()

    # 暂存解压出的数据库（临时目录退出即删除，需在块外完成替换）
    staged = backup_dir / ".restore_staged.db"
    try:
        with tempfile.TemporaryDirectory(dir=str(backup_dir)) as tmp:
            tmp_path = Path(tmp)

            # 1. 解密
            decrypted = tmp_path / "restore.tar.gz"
            decrypt_file(enc_path, decrypted)

            # 2. 校验 tar.gz 结构：必须含 keys.db
            with tarfile.open(decrypted, mode="r:gz") as tar:
                names = tar.getnames()
                if _TAR_MEMBER_DB not in names:
                    raise ValueError("备份文件无效：缺少 keys.db")
                if _TAR_MEMBER_META not in names:
                    raise ValueError("备份文件无效：缺少 meta.json")
                restored_db = tmp_path / "restored.db"
                with tar.extractfile(_TAR_MEMBER_DB) as f:
                    restored_db.write_bytes(f.read())

            # 3. 校验备份内数据库完整性（损坏则拒绝恢复，原库不动）
            _verify_db_integrity(restored_db)

            # 4. 移到临时目录之外，供块外原子替换
            shutil.move(str(restored_db), str(staged))

        # 5. 恢复前快照：当前库自动备份为 pre_restore，可回退
        snapshot = None
        if db_path.exists():
            try:
                snapshot = _create_backup_file(db_path, backup_dir, pre_restore=True)
            except Exception:
                # 快照失败不阻塞恢复（避免用户想恢复却因快照失败被卡住）
                print(f"[backup] 恢复前快照失败（忽略）: {filename}")

        # 6. 原子替换数据库文件，并清理与新库不匹配的 WAL/SHM 残留
        os.replace(str(staged), str(db_path))
        _remove_stale_wal_files(db_path)
    finally:
        # 清理暂存文件（替换成功后已不存在；失败时不留残渣）
        if staged.exists():
            staged.unlink(missing_ok=True)

    # 7. 触发重启（由 Docker restart policy 拉起加载新库）
    if restart:
        restart_process()

    return {"restored": filename, "pre_restore": snapshot["filename"] if snapshot else None}
