"""定时备份调度配置测试（配置读写层 + /backups/schedule 端点）。

功能范围（需求澄清结果）：
- 定时配置来源：环境变量 BACKUP_CRON / BACKUP_KEEP_DAYS 作为默认值，
  配置文件（默认 data/backup_schedule.json，BACKUP_SCHEDULE_FILE 可配）优先。
- 配置格式：{enabled: bool, cron: str, keep_days: int}
- cron 为空字符串时 enabled 必须为 False；enabled=True 时 cron 必须为合法 5 段表达式。
- keep_days 有效范围 1~365。
- GET 返回当前配置 + next_fire（enabled=False 时 next_fire 为 null）。

模块接口约定（由本测试先行定义）：
- app.services.backup_scheduler:
    get_schedule_file() -> Path
    get_schedule_config() -> dict   # {enabled, cron, keep_days, next_fire}
    save_schedule_config(enabled: bool, cron: str, keep_days: int) -> dict
- app.routers.backups（挂在 /backups 前缀）
    GET /backups/schedule                   查询当前调度配置
    PUT /backups/schedule                   更新调度配置（立即生效）
"""

import json

import pytest

from app.core import config
from app.services import backup_scheduler


# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------

def _make_schedule_file(tmp_path, data):
    """写入一个调度配置文件。"""
    path = tmp_path / "backup_schedule.json"
    path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    return path


def _monkeypatch_schedule_paths(monkeypatch, tmp_path):
    """把调度配置的路径解析指到测试隔离位置。"""
    monkeypatch.setattr(
        backup_scheduler, "get_schedule_file", lambda: tmp_path / "backup_schedule.json"
    )


def _monkeypatch_env_defaults(monkeypatch, cron="", keep_days=30):
    """把环境变量默认值指到指定值（模拟 BACKUP_CRON / BACKUP_KEEP_DAYS）。"""
    monkeypatch.setattr(config, "BACKUP_CRON", cron)
    monkeypatch.setattr(config, "BACKUP_KEEP_DAYS", keep_days)


def _api_key_headers():
    # 后端认证：API Key 需在库中存在，或回退 Admin 凭据（conftest 默认 admin/password）
    return {"X-Admin-User": "admin", "X-Admin-Pass": "password"}


# ---------------------------------------------------------------------------
# 一、配置读写层（app.services.backup_scheduler）
# ---------------------------------------------------------------------------

class TestScheduleConfigDefaults:
    def test_default_disabled_when_no_env(self, monkeypatch, tmp_path):
        """无环境变量且无配置文件时，应返回 enabled=False、cron 为空。"""
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        _monkeypatch_env_defaults(monkeypatch, cron="", keep_days=30)

        cfg = backup_scheduler.get_schedule_config()
        assert cfg["enabled"] is False
        assert cfg["cron"] == ""
        assert cfg["keep_days"] == 30
        assert cfg["next_fire"] is None

    def test_env_cron_enables_schedule(self, monkeypatch, tmp_path):
        """环境变量配置了 BACKUP_CRON 时应启用调度并计算 next_fire。"""
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        _monkeypatch_env_defaults(monkeypatch, cron="0 3 * * *", keep_days=7)

        cfg = backup_scheduler.get_schedule_config()
        assert cfg["enabled"] is True
        assert cfg["cron"] == "0 3 * * *"
        assert cfg["keep_days"] == 7
        assert cfg["next_fire"] is not None

    def test_schedule_file_overrides_env(self, monkeypatch, tmp_path):
        """配置文件存在时优先于环境变量。"""
        _make_schedule_file(
            tmp_path, {"enabled": True, "cron": "30 9 * * *", "keep_days": 14}
        )
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        _monkeypatch_env_defaults(monkeypatch, cron="0 3 * * *", keep_days=7)

        cfg = backup_scheduler.get_schedule_config()
        assert cfg["enabled"] is True
        assert cfg["cron"] == "30 9 * * *"
        assert cfg["keep_days"] == 14

    def test_missing_schedule_file_falls_back_to_env(self, monkeypatch, tmp_path):
        """配置文件不存在时回退环境变量，不崩溃。"""
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        _monkeypatch_env_defaults(monkeypatch, cron="15 6 * * 1", keep_days=45)

        cfg = backup_scheduler.get_schedule_config()
        assert cfg["enabled"] is True
        assert cfg["cron"] == "15 6 * * 1"
        assert cfg["keep_days"] == 45

    def test_corrupt_schedule_file_falls_back_to_env(self, monkeypatch, tmp_path):
        """配置文件损坏（非 JSON）时回退环境变量，不崩溃。"""
        path = tmp_path / "backup_schedule.json"
        path.write_text("{not valid json!!", encoding="utf-8")
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        _monkeypatch_env_defaults(monkeypatch, cron="0 2 * * *", keep_days=30)

        cfg = backup_scheduler.get_schedule_config()
        assert cfg["enabled"] is True
        assert cfg["cron"] == "0 2 * * *"
        assert cfg["keep_days"] == 30

    def test_schedule_file_missing_fields_falls_back(self, monkeypatch, tmp_path):
        """配置文件缺少字段时按字段回退默认值，不崩溃。"""
        _make_schedule_file(tmp_path, {"enabled": True})
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        _monkeypatch_env_defaults(monkeypatch, cron="", keep_days=30)

        cfg = backup_scheduler.get_schedule_config()
        # cron 缺失 → 视为空；enabled=True 但 cron 空 → 按禁用处理
        assert cfg["enabled"] is False
        assert cfg["keep_days"] == 30

    def test_disabled_config_has_null_next_fire(self, monkeypatch, tmp_path):
        """禁用状态（enabled=False）下 next_fire 应为 None。"""
        _make_schedule_file(
            tmp_path, {"enabled": False, "cron": "0 3 * * *", "keep_days": 30}
        )
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        _monkeypatch_env_defaults(monkeypatch, cron="", keep_days=30)

        cfg = backup_scheduler.get_schedule_config()
        assert cfg["enabled"] is False
        assert cfg["next_fire"] is None


class TestScheduleConfigSave:
    def test_save_and_read_back(self, monkeypatch, tmp_path):
        """保存后立即读取应返回相同配置，且 next_fire 指向未来。"""
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        _monkeypatch_env_defaults(monkeypatch, cron="", keep_days=30)

        result = backup_scheduler.save_schedule_config(
            enabled=True, cron="30 22 * * *", keep_days=10
        )
        assert result["enabled"] is True
        assert result["cron"] == "30 22 * * *"
        assert result["keep_days"] == 10

        cfg = backup_scheduler.get_schedule_config()
        assert cfg == result
        assert cfg["next_fire"] is not None

    def test_save_persists_to_file(self, monkeypatch, tmp_path):
        """保存的配置应写入配置文件（重启后仍在）。"""
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        _monkeypatch_env_defaults(monkeypatch, cron="", keep_days=30)

        backup_scheduler.save_schedule_config(
            enabled=True, cron="5 4 * * 1", keep_days=60
        )
        path = tmp_path / "backup_schedule.json"
        assert path.exists()
        data = json.loads(path.read_text(encoding="utf-8"))
        assert data == {"enabled": True, "cron": "5 4 * * 1", "keep_days": 60}

    def test_save_disabled_allows_empty_cron(self, monkeypatch, tmp_path):
        """enabled=False 时允许 cron 为空。"""
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        _monkeypatch_env_defaults(monkeypatch, cron="0 3 * * *", keep_days=30)

        result = backup_scheduler.save_schedule_config(
            enabled=False, cron="", keep_days=30
        )
        assert result["enabled"] is False
        assert result["cron"] == ""
        assert result["next_fire"] is None

    def test_save_enabled_with_empty_cron_raises(self, monkeypatch, tmp_path):
        """enabled=True 但 cron 为空应校验失败。"""
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        with pytest.raises(ValueError):
            backup_scheduler.save_schedule_config(
                enabled=True, cron="", keep_days=30
            )

    def test_save_invalid_cron_raises(self, monkeypatch, tmp_path):
        """非法 cron 表达式应校验失败。"""
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        for bad in ["61 * * * *", "1 2 3", "* * * *", "a b c d e", "0 3 * * * *"]:
            with pytest.raises(ValueError, match="cron"):
                backup_scheduler.save_schedule_config(
                    enabled=True, cron=bad, keep_days=30
                )

    def test_save_invalid_keep_days_raises(self, monkeypatch, tmp_path):
        """keep_days 越界（0、负数、超 365）或非数字应校验失败。"""
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        for bad in [0, -1, 366, 999]:
            with pytest.raises(ValueError, match="keep_days"):
                backup_scheduler.save_schedule_config(
                    enabled=True, cron="0 3 * * *", keep_days=bad
                )
        with pytest.raises(ValueError):
            backup_scheduler.save_schedule_config(
                enabled=True, cron="0 3 * * *", keep_days="abc"
            )

    def test_save_is_idempotent(self, monkeypatch, tmp_path):
        """重复保存相同配置应得到一致结果。"""
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        first = backup_scheduler.save_schedule_config(
            enabled=True, cron="0 3 * * *", keep_days=30
        )
        second = backup_scheduler.save_schedule_config(
            enabled=True, cron="0 3 * * *", keep_days=30
        )
        assert first == second

    def test_save_validation_failure_leaves_file_untouched(self, monkeypatch, tmp_path):
        """校验失败时不应写坏现有配置文件。"""
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        backup_scheduler.save_schedule_config(
            enabled=True, cron="0 3 * * *", keep_days=30
        )
        path = tmp_path / "backup_schedule.json"
        before = path.read_bytes()

        with pytest.raises(ValueError):
            backup_scheduler.save_schedule_config(
                enabled=True, cron="bad cron", keep_days=30
            )
        assert path.read_bytes() == before


# ---------------------------------------------------------------------------
# 二、/backups/schedule 端点
# ---------------------------------------------------------------------------

class TestScheduleAPI:
    def test_get_requires_auth(self, client):
        """无凭据查询调度配置应 401。"""
        resp = client.get("/backups/schedule")
        assert resp.status_code == 401

    def test_put_requires_auth(self, client):
        """无凭据更新调度配置应 401。"""
        resp = client.put("/backups/schedule", json={})
        assert resp.status_code == 401

    def test_get_returns_current_config(self, client, monkeypatch, tmp_path):
        """GET /backups/schedule 应返回当前配置。"""
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        _monkeypatch_env_defaults(monkeypatch, cron="", keep_days=30)

        resp = client.get("/backups/schedule", headers=_api_key_headers())
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert data["enabled"] is False
        assert data["cron"] == ""
        assert data["keep_days"] == 30
        assert data["next_fire"] is None

    def test_put_updates_config(self, client, monkeypatch, tmp_path):
        """PUT /backups/schedule 合法配置应返回 200 与新配置。"""
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        _monkeypatch_env_defaults(monkeypatch, cron="", keep_days=30)

        resp = client.put(
            "/backups/schedule",
            headers=_api_key_headers(),
            json={"enabled": True, "cron": "30 9 * * *", "keep_days": 15},
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert data["enabled"] is True
        assert data["cron"] == "30 9 * * *"
        assert data["keep_days"] == 15

    def test_put_then_get_returns_updated(self, client, monkeypatch, tmp_path):
        """PUT 后 GET 应返回更新后的配置（持久化生效）。"""
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        _monkeypatch_env_defaults(monkeypatch, cron="", keep_days=30)

        client.put(
            "/backups/schedule",
            headers=_api_key_headers(),
            json={"enabled": True, "cron": "10 8 * * *", "keep_days": 5},
        )
        resp = client.get("/backups/schedule", headers=_api_key_headers())
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert data["enabled"] is True
        assert data["cron"] == "10 8 * * *"
        assert data["keep_days"] == 5
        assert data["next_fire"] is not None

    def test_put_invalid_cron_returns_400(self, client, monkeypatch, tmp_path):
        """非法 cron 应 400 且不改变现有配置。"""
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        _monkeypatch_env_defaults(monkeypatch, cron="", keep_days=30)
        client.put(
            "/backups/schedule",
            headers=_api_key_headers(),
            json={"enabled": True, "cron": "0 3 * * *", "keep_days": 30},
        )

        resp = client.put(
            "/backups/schedule",
            headers=_api_key_headers(),
            json={"enabled": True, "cron": "99 * * * *", "keep_days": 30},
        )
        assert resp.status_code == 400, resp.text

        # 原配置未被破坏
        data = client.get("/backups/schedule", headers=_api_key_headers()).json()
        assert data["cron"] == "0 3 * * *"

    def test_put_enabled_with_empty_cron_returns_400(self, client, monkeypatch, tmp_path):
        """enabled=True 且 cron 为空应 400。"""
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        resp = client.put(
            "/backups/schedule",
            headers=_api_key_headers(),
            json={"enabled": True, "cron": "", "keep_days": 30},
        )
        assert resp.status_code == 400, resp.text

    def test_put_invalid_keep_days_returns_400(self, client, monkeypatch, tmp_path):
        """非法 keep_days 应 400。"""
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        resp = client.put(
            "/backups/schedule",
            headers=_api_key_headers(),
            json={"enabled": True, "cron": "0 3 * * *", "keep_days": 0},
        )
        assert resp.status_code == 400, resp.text

    def test_put_missing_fields_returns_422(self, client, monkeypatch, tmp_path):
        """缺少字段的请求体应 422（pydantic 校验失败）。"""
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        resp = client.put(
            "/backups/schedule",
            headers=_api_key_headers(),
            json={"enabled": True},
        )
        assert resp.status_code == 422, resp.text

    def test_put_disabled_ignores_invalid_cron(self, client, monkeypatch, tmp_path):
        """enabled=False 时 cron 为空合法；禁用后 next_fire 为 null。"""
        _monkeypatch_schedule_paths(monkeypatch, tmp_path)
        _monkeypatch_env_defaults(monkeypatch, cron="0 3 * * *", keep_days=30)

        resp = client.put(
            "/backups/schedule",
            headers=_api_key_headers(),
            json={"enabled": False, "cron": "", "keep_days": 30},
        )
        assert resp.status_code == 200, resp.text
        assert resp.json()["next_fire"] is None
