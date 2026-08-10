"""备份与恢复功能测试。

功能范围（需求澄清结果）：
- 备份对象：Shipyard 自身数据（SQLite 数据库 keys.db）
- 备份格式：tar.gz 压缩包（keys.db + meta.json），整体用 SECRET_KEY 派生密钥加密
- 触发方式：手动 REST API + 定时（BACKUP_CRON 环境变量，自实现 cron 解析线程）
- 存储位置：服务器本地目录（默认 data/backups/，环境变量 BACKUP_DIR 可配）
- 保留策略：按天数自动清理（BACKUP_KEEP_DAYS 可配）+ 手动删除
- 恢复行为：覆盖现有数据库，替换后自动重启服务

模块接口约定（由本测试先行定义）：
- app.core.backup_crypto:
    encrypt_file(src: Path, dst: Path, key: bytes|None) -> Path
    decrypt_file(src: Path, dst: Path, key: bytes|None) -> Path
- app.services.backup_scheduler:
    CronSchedule(expr: str)  # 标准 5 段 cron
        matches(dt: datetime) -> bool
        next_fire(after: datetime) -> datetime
- app.services.backup_service:
    get_db_path() -> Path / get_backup_dir() -> Path
    create_backup() -> BackupInfo（dict: filename/size/created_at）
    list_backups() -> List[BackupInfo]
    delete_backup(filename) -> None
    cleanup_old_backups(keep_days: int) -> int  # 删除数量
    restore_backup(filename, confirm: bool) -> None  # 覆盖 + 重启
    restart_process() -> None  # 恢复后触发服务重启（内部 os._exit(1)）
- app.routers.backups（挂在 /backups 前缀）
    POST   /backups                       手动创建备份
    GET    /backups                       备份列表
    DELETE /backups/{filename}            手动删除
    POST   /backups/{filename}/restore    恢复（需 confirm=true）
"""

import io
import json
import os
import sqlite3
import tarfile
import time
from datetime import datetime, timedelta

import pytest

# 备份目录/数据库路径依赖测试隔离：所有涉及文件的用例用 tmp_path，
# 服务层的路径解析函数通过 monkeypatch 指到临时位置。
from app.core import backup_crypto
from app.services import backup_service, backup_scheduler


# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------

def make_source_db(path, rows=None):
    """重建带数据的 SQLite 源数据库。

    rows 为 None 时写入 2 行（test-data 表）；rows 为 [] 时创建空表。
    重复调用会先删除旧表，保证可多次重建。
    """
    conn = sqlite3.connect(str(path))
    conn.execute("DROP TABLE IF EXISTS test_data")
    conn.execute("CREATE TABLE test_data (id INTEGER PRIMARY KEY, name TEXT)")
    if rows is None:
        rows = [(1, "alpha"), (2, "beta")]
    conn.executemany("INSERT INTO test_data VALUES (?,?)", rows)
    conn.commit()
    conn.close()
    return rows


def read_table(path):
    conn = sqlite3.connect(str(path))
    try:
        cur = conn.execute("SELECT id, name FROM test_data ORDER BY id")
        return cur.fetchall()
    finally:
        conn.close()


def set_mtime(path, days_ago):
    """把文件的修改时间改成 N 天前（模拟旧备份）。"""
    old = time.time() - days_ago * 86400
    os.utime(str(path), (old, old))


def decrypt_to_bytes(enc_path, key=None):
    """解密备份文件到内存 bytes（用于检查 tar.gz 内容）。"""
    out = enc_path.with_suffix(".dec")
    backup_crypto.decrypt_file(enc_path, out, key=key)
    return out.read_bytes()


def extract_backup(enc_path, key=None):
    """解密备份文件并展开 tar.gz，返回 (members_dict, tar_entries)。"""
    raw = decrypt_to_bytes(enc_path, key)
    tar = tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz")
    members = {m.name: m for m in tar.getmembers()}
    return members, tar


def monkeypatch_paths(monkeypatch, db_path, backup_dir):
    """把 backup_service 的路径解析指到测试隔离位置。"""
    monkeypatch.setattr(backup_service, "get_db_path", lambda: db_path)
    monkeypatch.setattr(backup_service, "get_backup_dir", lambda: backup_dir)
    return db_path, backup_dir


# ---------------------------------------------------------------------------
# 一、文件加密（app.core.backup_crypto）
# ---------------------------------------------------------------------------

class TestBackupCrypto:
    def test_roundtrip_small_file(self, tmp_path):
        """加密→解密应还原原始内容。"""
        src = tmp_path / "src.bin"
        src.write_bytes(b"hello shipyard backup" * 100)
        enc = tmp_path / "out.enc"
        dec = tmp_path / "out.dec"

        backup_crypto.encrypt_file(src, enc)
        backup_crypto.decrypt_file(enc, dec)

        assert dec.read_bytes() == src.read_bytes()

    def test_roundtrip_empty_file(self, tmp_path):
        """空文件也应能加密解密。"""
        src = tmp_path / "empty.bin"
        src.write_bytes(b"")
        enc = tmp_path / "empty.enc"
        dec = tmp_path / "empty.dec"

        backup_crypto.encrypt_file(src, enc)
        backup_crypto.decrypt_file(enc, dec)

        assert dec.read_bytes() == b""

    def test_roundtrip_large_file(self, tmp_path):
        """大文件（>4MB，验证流式分块不整读入内存）应正确往返。"""
        src = tmp_path / "big.bin"
        # 伪随机数据（不用 random 模块生成，保证可重复）
        data = bytes((i * 31 + 7) % 256 for i in range(4 * 1024 * 1024 + 12345))
        src.write_bytes(data)
        enc = tmp_path / "big.enc"
        dec = tmp_path / "big.dec"

        backup_crypto.encrypt_file(src, enc)
        backup_crypto.decrypt_file(enc, dec)

        assert dec.read_bytes() == data

    def test_encrypted_file_not_plaintext(self, tmp_path):
        """密文文件中不应出现明文内容。"""
        src = tmp_path / "src.bin"
        plain = b"TOP_SECRET_PLAINTEXT_XYZ"
        src.write_bytes(plain)

        enc = tmp_path / "out.enc"
        backup_crypto.encrypt_file(src, enc)

        enc_bytes = enc.read_bytes()
        assert plain not in enc_bytes
        assert b"TOP_SECRET" not in enc_bytes

    def test_encrypted_file_has_magic_header(self, tmp_path):
        """加密文件应以魔数头标识格式版本。"""
        src = tmp_path / "src.bin"
        src.write_bytes(b"data")
        enc = tmp_path / "out.enc"
        backup_crypto.encrypt_file(src, enc)
        head = enc.read_bytes()[:8]
        assert head == backup_crypto.MAGIC_HEADER

    def test_decrypt_with_different_key_fails(self, tmp_path):
        """使用不同密钥解密应失败（密钥由 SECRET_KEY 派生）。"""
        src = tmp_path / "src.bin"
        src.write_bytes(b"secret data")
        enc = tmp_path / "out.enc"
        backup_crypto.encrypt_file(src, enc, key=b"key-a")

        dec = tmp_path / "out.dec"
        with pytest.raises(Exception):
            backup_crypto.decrypt_file(enc, dec, key=b"key-b")
        # 失败后不应产生输出文件
        assert not dec.exists()

    def test_decrypt_tampered_ciphertext_fails(self, tmp_path):
        """篡改密文中间字节应触发 HMAC 校验失败。"""
        src = tmp_path / "src.bin"
        src.write_bytes(b"integrity matters" * 50)
        enc = tmp_path / "out.enc"
        backup_crypto.encrypt_file(src, enc)

        tampered = tmp_path / "tampered.enc"
        raw = bytearray(enc.read_bytes())
        raw[len(raw) // 2] ^= 0xFF  # 翻转中间一个字节
        tampered.write_bytes(bytes(raw))

        dec = tmp_path / "out.dec"
        with pytest.raises(Exception):
            backup_crypto.decrypt_file(tampered, dec)
        assert not dec.exists()

    def test_decrypt_truncated_file_fails(self, tmp_path):
        """截断的密文文件应解密失败。"""
        src = tmp_path / "src.bin"
        src.write_bytes(b"data" * 1000)
        enc = tmp_path / "out.enc"
        backup_crypto.encrypt_file(src, enc)

        raw = enc.read_bytes()
        truncated = tmp_path / "truncated.enc"
        truncated.write_bytes(raw[: len(raw) // 2])

        dec = tmp_path / "out.dec"
        with pytest.raises(Exception):
            backup_crypto.decrypt_file(truncated, dec)
        assert not dec.exists()

    def test_decrypt_garbage_fails(self, tmp_path):
        """垃圾数据（非加密文件）应解密失败。"""
        garbage = tmp_path / "garbage.enc"
        garbage.write_bytes(os.urandom(1024))

        dec = tmp_path / "out.dec"
        with pytest.raises(Exception):
            backup_crypto.decrypt_file(garbage, dec)
        assert not dec.exists()

    def test_decrypt_missing_source_fails(self, tmp_path):
        """源文件不存在应报错。"""
        with pytest.raises(Exception):
            backup_crypto.decrypt_file(tmp_path / "nope.enc", tmp_path / "x.dec")


# ---------------------------------------------------------------------------
# 二、cron 调度解析（app.services.backup_scheduler）
# ---------------------------------------------------------------------------

class TestCronSchedule:
    def test_every_minute_matches_any_time(self):
        """`* * * * *` 应匹配任意时刻。"""
        sched = backup_scheduler.CronSchedule("* * * * *")
        for dt in [
            datetime(2026, 8, 10, 0, 0),
            datetime(2026, 8, 10, 23, 59),
            datetime(2026, 1, 1, 12, 30),
            datetime(2026, 12, 31, 0, 1),
        ]:
            assert sched.matches(dt), f"应匹配 {dt}"

    def test_specific_hour_minute_matches_only_exact(self):
        """`30 3 * * *` 只在每天 03:30 匹配。"""
        sched = backup_scheduler.CronSchedule("30 3 * * *")
        assert sched.matches(datetime(2026, 8, 10, 3, 30))
        assert not sched.matches(datetime(2026, 8, 10, 3, 31))
        assert not sched.matches(datetime(2026, 8, 10, 2, 30))
        assert not sched.matches(datetime(2026, 8, 10, 15, 30))

    def test_step_syntax(self):
        """`*/5 * * * *` 每 5 分钟匹配一次。"""
        sched = backup_scheduler.CronSchedule("*/5 * * * *")
        assert sched.matches(datetime(2026, 8, 10, 10, 0))
        assert sched.matches(datetime(2026, 8, 10, 10, 55))
        assert not sched.matches(datetime(2026, 8, 10, 10, 3))
        assert not sched.matches(datetime(2026, 8, 10, 10, 58))

    def test_range_syntax(self):
        """`0 1-5 * * *` 小时为 1~5 才匹配。"""
        sched = backup_scheduler.CronSchedule("0 1-5 * * *")
        assert sched.matches(datetime(2026, 8, 10, 1, 0))
        assert sched.matches(datetime(2026, 8, 10, 5, 0))
        assert not sched.matches(datetime(2026, 8, 10, 6, 0))
        assert not sched.matches(datetime(2026, 8, 10, 0, 0))

    def test_list_syntax(self):
        """`0,30 * * * *` 整分和 30 分匹配。"""
        sched = backup_scheduler.CronSchedule("0,30 * * * *")
        assert sched.matches(datetime(2026, 8, 10, 7, 0))
        assert sched.matches(datetime(2026, 8, 10, 7, 30))
        assert not sched.matches(datetime(2026, 8, 10, 7, 15))

    def test_weekday_expression(self):
        """`0 3 * * 1-5` 仅工作日匹配。"""
        # 2026-08-10 是周一
        monday = datetime(2026, 8, 10, 3, 0)
        sunday = datetime(2026, 8, 9, 3, 0)  # 2026-08-09 周日
        sched = backup_scheduler.CronSchedule("0 3 * * 1-5")
        assert sched.matches(monday)
        assert not sched.matches(sunday)

    def test_next_fire_computes_later_time(self):
        """next_fire 应返回下一个触发时刻（严格晚于 after）。"""
        sched = backup_scheduler.CronSchedule("30 3 * * *")
        nxt = sched.next_fire(datetime(2026, 8, 10, 3, 30))
        assert nxt == datetime(2026, 8, 11, 3, 30)

        nxt2 = sched.next_fire(datetime(2026, 8, 10, 3, 29, 59))
        assert nxt2 == datetime(2026, 8, 10, 3, 30)

    def test_next_fire_never_for_invalid_after(self):
        """next_fire 总是返回未来时刻。"""
        sched = backup_scheduler.CronSchedule("0 3 * * *")
        nxt = sched.next_fire(datetime(2026, 8, 10, 3, 0, 30))
        assert nxt > datetime(2026, 8, 10, 3, 0, 30)

    @pytest.mark.parametrize(
        "expr",
        [
            "",                      # 空字符串
            "0 3 * *",               # 只有 4 段
            "0 3 * * * *",           # 6 段
            "60 3 * * *",            # 分钟越界
            "0 25 * * *",            # 小时越界
            "0 3 32 * *",            # 日越界
            "abc * * * *",           # 非数字
            "0, * * * *",            # 空列表项
            "1-5-9 * * * *",         # 非法范围
            "*/ * * * *",            # 非法步长
        ],
    )
    def test_invalid_expressions_raise(self, expr):
        """非法 cron 表达式必须抛出异常，不能静默接受。"""
        with pytest.raises(Exception):
            backup_scheduler.CronSchedule(expr)


# ---------------------------------------------------------------------------
# 三、备份服务（app.services.backup_service）
# ---------------------------------------------------------------------------

class TestBackupServiceCreate:
    def test_create_backup_creates_encrypted_file(self, tmp_path, monkeypatch):
        """创建备份应生成加密文件（有魔数头，无明文库内容）。"""
        db = tmp_path / "keys.db"
        make_source_db(db)
        monkeypatch_paths(monkeypatch, db, tmp_path / "backups")

        info = backup_service.create_backup()

        assert info["filename"].endswith(".tar.gz.enc")
        enc_path = tmp_path / "backups" / info["filename"]
        assert enc_path.exists()
        assert enc_path.read_bytes()[:8] == backup_crypto.MAGIC_HEADER
        # 备份文件里不应出现数据库明文内容
        raw = enc_path.read_bytes()
        assert b"alpha" not in raw
        assert b"test_data" not in raw

    def test_backup_contains_db_and_meta(self, tmp_path, monkeypatch):
        """解密展开后应含 keys.db 和 meta.json（含时间戳）。"""
        db = tmp_path / "keys.db"
        make_source_db(db)
        backup_dir = tmp_path / "backups"
        monkeypatch_paths(monkeypatch, db, backup_dir)

        info = backup_service.create_backup()
        enc_path = backup_dir / info["filename"]
        members, tar = extract_backup(enc_path)
        assert "keys.db" in members
        assert "meta.json" in members
        meta = json.loads(tar.extractfile("meta.json").read())
        assert "created_at" in meta
        # meta 时间戳与文件名时间一致（文件名 backup_YYYYMMDD_HHMMSS，meta 去掉下划线）
        assert meta["created_at"] == info["filename"][7:22].replace("_", "")
        assert meta.get("table_count", 0) >= 1

    def test_backup_content_matches_source_db(self, tmp_path, monkeypatch):
        """备份库的数据应与源库一致。"""
        db = tmp_path / "keys.db"
        make_source_db(db, [(1, "alpha"), (2, "beta"), (3, "gamma")])
        backup_dir = tmp_path / "backups"
        monkeypatch_paths(monkeypatch, db, backup_dir)

        info = backup_service.create_backup()
        enc_path = backup_dir / info["filename"]
        members, tar = extract_backup(enc_path)
        db_member = members["keys.db"]
        with tar.extractfile(db_member) as f:
            data = f.read()
        extracted = tmp_path / "extracted.db"
        extracted.write_bytes(data)
        assert read_table(extracted) == [(1, "alpha"), (2, "beta"), (3, "gamma")]

    def test_create_backup_with_empty_db(self, tmp_path, monkeypatch):
        """空数据库也应能正常备份。"""
        db = tmp_path / "keys.db"
        make_source_db(db, rows=[])
        backup_dir = tmp_path / "backups"
        monkeypatch_paths(monkeypatch, db, backup_dir)

        info = backup_service.create_backup()
        enc_path = backup_dir / info["filename"]
        assert enc_path.exists()
        assert enc_path.stat().st_size > 0

    def test_create_backup_missing_db_raises(self, tmp_path, monkeypatch):
        """数据库文件不存在时应报错而不是生成损坏备份。"""
        backup_dir = tmp_path / "backups"
        monkeypatch_paths(monkeypatch, tmp_path / "nope.db", backup_dir)
        with pytest.raises(Exception):
            backup_service.create_backup()

    def test_create_backup_creates_dir_if_missing(self, tmp_path, monkeypatch):
        """备份目录不存在时应自动创建。"""
        db = tmp_path / "keys.db"
        make_source_db(db)
        backup_dir = tmp_path / "deep" / "nested" / "backups"
        monkeypatch_paths(monkeypatch, db, backup_dir)

        info = backup_service.create_backup()
        assert (backup_dir / info["filename"]).exists()


class TestBackupServiceList:
    def test_list_backups_returns_files(self, tmp_path, monkeypatch):
        """列表应返回文件名/大小/创建时间，按时间倒序。"""
        db = tmp_path / "keys.db"
        make_source_db(db)
        backup_dir = tmp_path / "backups"
        monkeypatch_paths(monkeypatch, db, backup_dir)

        backup_service.create_backup()
        time.sleep(1.1)  # 保证第二次文件名时间戳不同
        backup_service.create_backup()

        items = backup_service.list_backups()
        assert len(items) == 2
        # 倒序：新的在前
        assert items[0]["filename"] > items[1]["filename"]
        for item in items:
            assert item["size"] > 0
            assert item["created_at"]

    def test_list_backups_empty_dir(self, tmp_path, monkeypatch):
        """空目录应返回空列表。"""
        backup_dir = tmp_path / "backups"
        monkeypatch_paths(monkeypatch, tmp_path / "keys.db", backup_dir)
        assert backup_service.list_backups() == []

    def test_list_backups_ignores_foreign_files(self, tmp_path, monkeypatch):
        """目录中的非备份文件不应出现在列表里。"""
        db = tmp_path / "keys.db"
        make_source_db(db)
        backup_dir = tmp_path / "backups"
        backup_dir.mkdir()
        monkeypatch_paths(monkeypatch, db, backup_dir)
        (backup_dir / "junk.txt").write_text("not a backup")

        backup_service.create_backup()
        items = backup_service.list_backups()
        assert len(items) == 1
        assert items[0]["filename"].endswith(".tar.gz.enc")


class TestBackupServiceDelete:
    def test_delete_backup_removes_file(self, tmp_path, monkeypatch):
        """手动删除应移除文件。"""
        db = tmp_path / "keys.db"
        make_source_db(db)
        backup_dir = tmp_path / "backups"
        monkeypatch_paths(monkeypatch, db, backup_dir)

        info = backup_service.create_backup()
        backup_service.delete_backup(info["filename"])
        assert not (backup_dir / info["filename"]).exists()
        assert backup_service.list_backups() == []

    def test_delete_nonexistent_raises(self, tmp_path, monkeypatch):
        """删除不存在的备份应抛异常。"""
        backup_dir = tmp_path / "backups"
        monkeypatch_paths(monkeypatch, tmp_path / "keys.db", backup_dir)
        with pytest.raises(FileNotFoundError):
            backup_service.delete_backup("backup_99990101_010101.tar.gz.enc")

    def test_delete_ignores_non_backup_files(self, tmp_path, monkeypatch):
        """不允许通过删除接口删掉目录里的非备份文件。"""
        backup_dir = tmp_path / "backups"
        backup_dir.mkdir()
        monkeypatch_paths(monkeypatch, tmp_path / "keys.db", backup_dir)
        (backup_dir / "keys.db").write_text("real db")
        with pytest.raises(Exception):
            backup_service.delete_backup("keys.db")
        assert (backup_dir / "keys.db").exists()


class TestBackupServiceCleanup:
    def test_cleanup_removes_only_expired(self, tmp_path, monkeypatch):
        """只删除超过保留天数的备份，新备份保留。"""
        db = tmp_path / "keys.db"
        make_source_db(db)
        backup_dir = tmp_path / "backups"
        monkeypatch_paths(monkeypatch, db, backup_dir)

        backup_service.create_backup()
        old1 = backup_dir / "backup_20260701_000000.tar.gz.enc"
        old2 = backup_dir / "backup_20260710_000000.tar.gz.enc"
        fresh = backup_dir / "backup_20260809_000000.tar.gz.enc"
        old1.write_bytes(b"x")
        old2.write_bytes(b"x")
        fresh.write_bytes(b"x")
        set_mtime(old1, 40)
        set_mtime(old2, 31)
        set_mtime(fresh, 1)

        deleted = backup_service.cleanup_old_backups(keep_days=30)

        assert deleted == 2
        assert not old1.exists()
        assert not old2.exists()
        assert fresh.exists()

    def test_cleanup_keep_days_zero_deletes_all(self, tmp_path, monkeypatch):
        """keep_days=0 时删除所有备份。"""
        backup_dir = tmp_path / "backups"
        backup_dir.mkdir()
        monkeypatch_paths(monkeypatch, tmp_path / "keys.db", backup_dir)
        for name in ["backup_20260801_000000.tar.gz.enc", "backup_20260810_000000.tar.gz.enc"]:
            (backup_dir / name).write_bytes(b"x")
            set_mtime(backup_dir / name, 1)

        deleted = backup_service.cleanup_old_backups(keep_days=0)
        assert deleted == 2

    def test_cleanup_keeps_files_within_keep_days(self, tmp_path, monkeypatch):
        """保留天数边界内的备份不应删除（仅 mtime 超过 keep_days 才删）。

        mtime 精确等于 30 天整会与运行时的 now 产生毫秒级浮点竞态，
        这里用 30 天前 1 秒（仍在保留期内）模拟边界。
        """
        backup_dir = tmp_path / "backups"
        backup_dir.mkdir()
        monkeypatch_paths(monkeypatch, tmp_path / "keys.db", backup_dir)
        edge = backup_dir / "backup_20260711_000000.tar.gz.enc"
        edge.write_bytes(b"x")
        set_mtime(edge, 30 - 1 / 86400)  # 30 天前 1 秒（保留期内）

        deleted = backup_service.cleanup_old_backups(keep_days=30)
        assert deleted == 0
        assert edge.exists()

    def test_cleanup_ignores_foreign_files(self, tmp_path, monkeypatch):
        """清理时不应删除目录里的非备份文件。"""
        backup_dir = tmp_path / "backups"
        backup_dir.mkdir()
        monkeypatch_paths(monkeypatch, tmp_path / "keys.db", backup_dir)
        foreign = backup_dir / "junk.txt"
        foreign.write_text("keep me")
        set_mtime(foreign, 100)

        backup_service.cleanup_old_backups(keep_days=1)
        assert foreign.exists()


# ---------------------------------------------------------------------------
# 四、恢复（app.services.backup_service.restore_backup）
# ---------------------------------------------------------------------------

class TestRestore:
    def _setup(self, tmp_path, monkeypatch):
        db = tmp_path / "keys.db"
        backup_dir = tmp_path / "backups"
        monkeypatch_paths(monkeypatch, db, backup_dir)
        monkeypatch.setattr(backup_service, "restart_process", lambda: None)
        return db, backup_dir

    def test_restore_replaces_database_content(self, tmp_path, monkeypatch):
        """恢复后数据库内容应为备份时的内容。"""
        db, backup_dir = self._setup(tmp_path, monkeypatch)
        make_source_db(db, [(1, "alpha")])
        info = backup_service.create_backup()

        # 备份后数据库内容改变
        make_source_db(db, [(1, "changed"), (2, "new")])

        backup_service.restore_backup(info["filename"], confirm=True)
        assert read_table(db) == [(1, "alpha")]

    def test_restore_requires_confirm(self, tmp_path, monkeypatch):
        """confirm=False 必须拒绝，且数据库不变、不重启。"""
        db, backup_dir = self._setup(tmp_path, monkeypatch)
        make_source_db(db, [(1, "alpha")])
        info = backup_service.create_backup()
        make_source_db(db, [(2, "beta")])

        with pytest.raises(Exception):
            backup_service.restore_backup(info["filename"], confirm=False)
        assert read_table(db) == [(2, "beta")]

    def test_restore_nonexistent_file_raises(self, tmp_path, monkeypatch):
        """恢复不存在的备份应报错。"""
        db, backup_dir = self._setup(tmp_path, monkeypatch)
        make_source_db(db)
        with pytest.raises(FileNotFoundError):
            backup_service.restore_backup("backup_19990101_010101.tar.gz.enc", confirm=True)

    def test_restore_path_traversal_rejected(self, tmp_path, monkeypatch):
        """含路径穿越的文件名（../../）应被拒绝，不得访问目录外文件。"""
        db, backup_dir = self._setup(tmp_path, monkeypatch)
        make_source_db(db)
        with pytest.raises(Exception):
            backup_service.restore_backup("../../etc/passwd", confirm=True)

    def test_restore_creates_pre_restore_snapshot(self, tmp_path, monkeypatch):
        """恢复前应生成 pre_restore 快照，恢复后可回退。"""
        db, backup_dir = self._setup(tmp_path, monkeypatch)
        make_source_db(db, [(1, "alpha")])
        info = backup_service.create_backup()
        make_source_db(db, [(9, "current")])

        backup_service.restore_backup(info["filename"], confirm=True)

        pre_restore = [f for f in (backup_dir).iterdir() if "pre_restore" in f.name]
        assert len(pre_restore) == 1
        # 快照包含恢复前的数据（可以回退）
        members, tar = extract_backup(pre_restore[0])
        extracted = tmp_path / "pre.db"
        with tar.extractfile(members["keys.db"]) as f:
            extracted.write_bytes(f.read())
        assert read_table(extracted) == [(9, "current")]

    def test_restore_calls_restart(self, tmp_path, monkeypatch):
        """恢复成功后必须触发进程重启。"""
        db, backup_dir = self._setup(tmp_path, monkeypatch)
        make_source_db(db)
        info = backup_service.create_backup()

        restarted = []
        monkeypatch.setattr(backup_service, "restart_process", lambda: restarted.append(1))
        backup_service.restore_backup(info["filename"], confirm=True)
        assert restarted == [1]

    def test_restore_tampered_backup_raises_and_keeps_db(self, tmp_path, monkeypatch):
        """篡改的备份应拒绝恢复，原数据库保持不动。"""
        db, backup_dir = self._setup(tmp_path, monkeypatch)
        make_source_db(db, [(1, "alpha")])
        info = backup_service.create_backup()
        make_source_db(db, [(2, "beta")])

        enc_path = backup_dir / info["filename"]
        raw = bytearray(enc_path.read_bytes())
        raw[len(raw) // 3] ^= 0xFF
        enc_path.write_bytes(bytes(raw))

        with pytest.raises(Exception):
            backup_service.restore_backup(info["filename"], confirm=True)
        assert read_table(db) == [(2, "beta")]

    def test_restore_invalid_archive_raises(self, tmp_path, monkeypatch):
        """解密成功但不是合法 tar.gz 的内容应拒绝恢复。"""
        db, backup_dir = self._setup(tmp_path, monkeypatch)
        make_source_db(db, [(1, "alpha")])

        bogus = tmp_path / "bogus.db"
        bogus.write_bytes(b"not a database" * 100)
        backup_crypto.encrypt_file(bogus, backup_dir / "backup_20260810_000000.tar.gz.enc")

        with pytest.raises(Exception):
            backup_service.restore_backup("backup_20260810_000000.tar.gz.enc", confirm=True)
        assert read_table(db) == [(1, "alpha")]

    def test_restore_corrupt_db_inside_backup_raises(self, tmp_path, monkeypatch):
        """备份内部 keys.db 损坏（非 SQLite）时应拒绝，原库不动。"""
        db, backup_dir = self._setup(tmp_path, monkeypatch)
        make_source_db(db, [(1, "alpha")])

        # 手工构造：tar.gz 里放损坏的 db + meta.json
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w:gz") as tar:
            bad = tmp_path / "bad.db"
            bad.write_bytes(b"garbage-not-sqlite")
            tar.add(bad, arcname="keys.db")
            meta = tmp_path / "meta.json"
            meta.write_text(json.dumps({"created_at": "20260810000000"}))
            tar.add(meta, arcname="meta.json")
        packed = tmp_path / "packed.tar.gz"
        packed.write_bytes(buf.getvalue())
        enc = backup_dir / "backup_20260810_000000.tar.gz.enc"
        backup_crypto.encrypt_file(packed, enc)

        with pytest.raises(Exception):
            backup_service.restore_backup("backup_20260810_000000.tar.gz.enc", confirm=True)
        assert read_table(db) == [(1, "alpha")]

    def test_restore_backup_missing_db_member_raises(self, tmp_path, monkeypatch):
        """tar.gz 里缺少 keys.db 成员时应拒绝。"""
        db, backup_dir = self._setup(tmp_path, monkeypatch)
        make_source_db(db, [(1, "alpha")])

        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w:gz") as tar:
            meta = tmp_path / "meta.json"
            meta.write_text(json.dumps({"created_at": "20260810000000"}))
            tar.add(meta, arcname="meta.json")
        packed = tmp_path / "packed2.tar.gz"
        packed.write_bytes(buf.getvalue())
        enc = backup_dir / "backup_20260810_000000.tar.gz.enc"
        backup_crypto.encrypt_file(packed, enc)

        with pytest.raises(Exception):
            backup_service.restore_backup("backup_20260810_000000.tar.gz.enc", confirm=True)
        assert read_table(db) == [(1, "alpha")]

    def test_restore_restart_false_skips_restart(self, tmp_path, monkeypatch):
        """restart=False 时不触发进程重启（由 REST 端点响应后延迟重启）。"""
        db, backup_dir = self._setup(tmp_path, monkeypatch)
        make_source_db(db, [(1, "alpha")])
        info = backup_service.create_backup()
        make_source_db(db, [(2, "beta")])

        restarted = []
        monkeypatch.setattr(backup_service, "restart_process", lambda: restarted.append(1))
        result = backup_service.restore_backup(info["filename"], confirm=True, restart=False)
        assert restarted == []  # 不立即重启
        assert read_table(db) == [(1, "alpha")]  # 数据已恢复
        assert result["restored"] == info["filename"]

    def test_restore_cleans_stale_wal_files(self, tmp_path, monkeypatch):
        """替换数据库后应清理残留的 keys.db-wal / keys.db-shm。

        WAL/SHM 属于旧 inode，与新主文件不匹配，残留会导致新进程
        打开时误回放旧日志或报错（生产实测恢复后服务无法启动的根因之一）。
        """
        db, backup_dir = self._setup(tmp_path, monkeypatch)
        make_source_db(db, [(1, "alpha")])
        info = backup_service.create_backup()

        # 模拟 WAL 模式下残留的 wal/shm 文件（旧 inode 属于被替换的库）
        stale_wal = tmp_path / "keys.db-wal"
        stale_shm = tmp_path / "keys.db-shm"
        stale_wal.write_bytes(b"fake-wal-content")
        stale_shm.write_bytes(b"fake-shm-content")

        backup_service.restore_backup(info["filename"], confirm=True)
        assert not stale_wal.exists(), "恢复后 keys.db-wal 应被清理"
        assert not stale_shm.exists(), "恢复后 keys.db-shm 应被清理"


def test_restart_process_kills_reloader_parent(monkeypatch):
    """restart_process 应 SIGKILL 父进程（uvicorn --reload 的 reloader）。

    容器主进程是 reloader 时，worker 自行 os._exit 不会触发 Docker
    restart policy（reloader 只等待文件变化，不监视 worker 存活），
    必须终止 reloader 让容器重启——否则恢复后服务永久挂起
    （生产实测 507/508 恢复后后端起不来的根因）。
    """
    import os
    import signal

    killed = []
    exited = []
    monkeypatch.setattr(backup_service.os, "kill", lambda pid, sig: killed.append((pid, sig)))
    monkeypatch.setattr(backup_service.os, "_exit", lambda code: exited.append(code))
    backup_service.restart_process()
    # 有父进程时必须 SIGKILL 父进程（reloader）
    assert killed and killed[0] == (os.getppid(), signal.SIGKILL)
    assert exited == [1]


def test_restart_process_exits_when_no_parent(monkeypatch):
    """无父进程（ppid=0，worker 即容器主进程，非 --reload 部署）时直接 os._exit。

    此时进程退出即容器主进程退出，Docker restart policy 自动拉起新容器。
    """
    killed = []
    exited = []
    monkeypatch.setattr(backup_service.os, "kill", lambda pid, sig: killed.append((pid, sig)))
    monkeypatch.setattr(backup_service.os, "_exit", lambda code: exited.append(code))
    monkeypatch.setattr(backup_service.os, "getppid", lambda: 0)
    backup_service.restart_process()
    assert killed == []  # 无父进程不 kill
    assert exited == [1]


def test_restart_process_kill_error_falls_back_to_exit(monkeypatch):
    """kill 父进程失败（如权限受限）时不影响 os._exit 兜底。"""
    import os

    exited = []
    monkeypatch.setattr(backup_service.os, "kill", lambda pid, sig: (_ for _ in ()).throw(OSError("no permission")))
    monkeypatch.setattr(backup_service.os, "_exit", lambda code: exited.append(code))
    backup_service.restart_process()
    assert exited == [1]


# ---------------------------------------------------------------------------
# 五、REST API（app.routers.backups，挂在 /backups 前缀）
# ---------------------------------------------------------------------------

def _api_key_headers():
    # 后端认证：API Key 需在库中存在，或回退 Admin 凭据（conftest 默认 admin/password）
    return {"X-Admin-User": "admin", "X-Admin-Pass": "password"}


class TestBackupAPI:
    def test_create_requires_auth(self, client):
        """无凭据手动备份应 401。"""
        resp = client.post("/backups")
        assert resp.status_code == 401

    def test_list_requires_auth(self, client):
        """无凭据查看列表应 401。"""
        resp = client.get("/backups")
        assert resp.status_code == 401

    def test_create_backup_endpoint(self, client, monkeypatch, tmp_path):
        """POST /backups 应创建备份并返回 201 与备份信息。"""
        db = tmp_path / "keys.db"
        make_source_db(db)
        monkeypatch_paths(monkeypatch, db, tmp_path / "backups")

        resp = client.post("/backups", headers=_api_key_headers())
        assert resp.status_code == 201, resp.text
        data = resp.json()
        assert data["filename"].endswith(".tar.gz.enc")
        assert data["size"] > 0

    def test_list_endpoint(self, client, monkeypatch, tmp_path):
        """GET /backups 应返回备份列表。"""
        db = tmp_path / "keys.db"
        make_source_db(db)
        monkeypatch_paths(monkeypatch, db, tmp_path / "backups")
        client.post("/backups", headers=_api_key_headers())

        resp = client.get("/backups", headers=_api_key_headers())
        assert resp.status_code == 200
        items = resp.json()
        assert len(items) == 1
        assert items[0]["filename"].endswith(".tar.gz.enc")

    def test_delete_endpoint(self, client, monkeypatch, tmp_path):
        """DELETE /backups/{filename} 应删除文件。"""
        db = tmp_path / "keys.db"
        make_source_db(db)
        backup_dir = tmp_path / "backups"
        monkeypatch_paths(monkeypatch, db, backup_dir)
        info = client.post("/backups", headers=_api_key_headers()).json()

        resp = client.delete(f"/backups/{info['filename']}", headers=_api_key_headers())
        assert resp.status_code == 200, resp.text
        assert not (backup_dir / info["filename"]).exists()

    def test_delete_nonexistent_endpoint(self, client, monkeypatch, tmp_path):
        """删除不存在的备份应 404。"""
        monkeypatch_paths(monkeypatch, tmp_path / "keys.db", tmp_path / "backups")
        resp = client.delete(
            "/backups/backup_19990101_010101.tar.gz.enc", headers=_api_key_headers()
        )
        assert resp.status_code == 404

    def test_restore_endpoint_requires_confirm(self, client, monkeypatch, tmp_path):
        """恢复不带 confirm=true 应 400。"""
        db = tmp_path / "keys.db"
        make_source_db(db)
        monkeypatch_paths(monkeypatch, db, tmp_path / "backups")
        info = client.post("/backups", headers=_api_key_headers()).json()

        resp = client.post(
            f"/backups/{info['filename']}/restore", headers=_api_key_headers()
        )
        assert resp.status_code == 400, resp.text

    def test_restore_endpoint_with_confirm(self, client, monkeypatch, tmp_path):
        """带 confirm=true 恢复应成功并触发重启。"""
        db = tmp_path / "keys.db"
        make_source_db(db, [(1, "alpha")])
        monkeypatch_paths(monkeypatch, db, tmp_path / "backups")
        restarted = []
        monkeypatch.setattr(
            backup_service, "restart_process", lambda: restarted.append(1)
        )
        info = client.post("/backups", headers=_api_key_headers()).json()
        make_source_db(db, [(1, "changed")])

        resp = client.post(
            f"/backups/{info['filename']}/restore?confirm=true",
            headers=_api_key_headers(),
        )
        assert resp.status_code == 200, resp.text
        assert restarted == [1]
        assert read_table(db) == [(1, "alpha")]

    def test_restore_nonexistent_endpoint(self, client, monkeypatch, tmp_path):
        """恢复不存在的备份应 404。"""
        monkeypatch_paths(monkeypatch, tmp_path / "keys.db", tmp_path / "backups")
        resp = client.post(
            "/backups/backup_19990101_010101.tar.gz.enc/restore?confirm=true",
            headers=_api_key_headers(),
        )
        assert resp.status_code == 404


class TestBackupDownloadAPI:
    def test_download_requires_auth(self, client):
        """无凭据下载备份应 401。"""
        resp = client.get("/backups/backup_19990101_010101.tar.gz.enc/download")
        assert resp.status_code == 401

    def test_download_returns_file_content(self, client, monkeypatch, tmp_path):
        """下载应返回加密备份文件的完整内容与文件名。"""
        db = tmp_path / "keys.db"
        make_source_db(db)
        backup_dir = tmp_path / "backups"
        monkeypatch_paths(monkeypatch, db, backup_dir)
        info = client.post("/backups", headers=_api_key_headers()).json()
        filename = info["filename"]

        resp = client.get(
            f"/backups/{filename}/download", headers=_api_key_headers()
        )
        assert resp.status_code == 200, resp.text
        assert resp.content == (backup_dir / filename).read_bytes()
        assert "attachment" in resp.headers.get("content-disposition", "")
        assert filename in resp.headers.get("content-disposition", "")

    def test_download_nonexistent_returns_404(self, client, monkeypatch, tmp_path):
        """下载不存在的备份应 404。"""
        monkeypatch_paths(monkeypatch, tmp_path / "keys.db", tmp_path / "backups")
        resp = client.get(
            "/backups/backup_19990101_010101.tar.gz.enc/download",
            headers=_api_key_headers(),
        )
        assert resp.status_code == 404

    def test_download_path_traversal_rejected(self, client, monkeypatch, tmp_path):
        """路径穿越文件名（../ 等）应被拒绝。"""
        monkeypatch_paths(monkeypatch, tmp_path / "keys.db", tmp_path / "backups")
        for bad in [
            "../backup_19990101_010101.tar.gz.enc",
            "backup_19990101_010101.tar.gz.enc/../../etc/passwd",
            "..%2fbackup_19990101_010101.tar.gz.enc",
        ]:
            resp = client.get(
                f"/backups/{bad}/download", headers=_api_key_headers()
            )
            assert resp.status_code in (400, 404), f"路径穿越应被拒绝: {bad}"

    def test_download_foreign_file_rejected(self, client, monkeypatch, tmp_path):
        """非备份命名规范的文件（如普通 txt）应被拒绝。"""
        monkeypatch_paths(monkeypatch, tmp_path / "keys.db", tmp_path / "backups")
        resp = client.get(
            "/backups/not_a_backup.txt/download", headers=_api_key_headers()
        )
        assert resp.status_code == 400, resp.text
