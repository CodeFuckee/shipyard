"""backup_restore 备份/恢复工具的单元测试（离线可跑，不依赖生产环境）。

覆盖场景：
- per-host API key 解析（全局 / 按主机覆盖 / 缺失）
- 备份目标过滤（只保留配置了 API key 的环境）
- 创建备份：URL 构建、响应解析、HTTP 错误透传
- 恢复备份：confirm 参数、备份文件名合法性校验、错误透传
- 服务恢复等待：立即成功 / 延迟成功 / 超时 / 零超时

与生产环境相关的行为（真实调用 create/restore API）由
test_prod_connect.py 在配置了 TEST_API_KEY 的 CI 上端到端覆盖。
"""

from unittest import mock

import pytest

import backup_restore


# ---------------------------------------------------------------------------
# per_host_api_key —— API key 按主机覆盖解析
# ---------------------------------------------------------------------------


def test_per_host_api_key_global(monkeypatch):
    """仅配置全局 TEST_API_KEY 时，任何主机都返回该 key。"""
    monkeypatch.setenv("TEST_API_KEY", "glpat-global")
    monkeypatch.delenv("TEST_API_KEY_10_0_0_122", raising=False)
    assert backup_restore.per_host_api_key("http://10.0.0.122:8080") == "glpat-global"


def test_per_host_api_key_host_override(monkeypatch):
    """配置 TEST_API_KEY_<host> 时，该主机优先使用覆盖值。"""
    monkeypatch.setenv("TEST_API_KEY", "glpat-global")
    monkeypatch.setenv("TEST_API_KEY_10_0_0_122", "glpat-inner")
    assert backup_restore.per_host_api_key("http://10.0.0.122:8080") == "glpat-inner"
    # 其他主机不受覆盖变量影响
    assert backup_restore.per_host_api_key("https://home.chenkaidi.top:507") == "glpat-global"


def test_per_host_api_key_missing(monkeypatch):
    """全局与按主机均未配置时返回空串。"""
    monkeypatch.delenv("TEST_API_KEY", raising=False)
    monkeypatch.delenv("TEST_API_KEY_10_0_0_122", raising=False)
    assert backup_restore.per_host_api_key("http://10.0.0.122:8080") == ""


def test_per_host_api_key_https_port_host(monkeypatch):
    """带端口、https 的主机名正确参与覆盖匹配（. 替换为 _，端口不参与）。"""
    monkeypatch.setenv("TEST_API_KEY", "glpat-global")
    monkeypatch.setenv("TEST_API_KEY_home_chenkaidi_top", "glpat-public")
    assert (
        backup_restore.per_host_api_key("https://home.chenkaidi.top:507")
        == "glpat-public"
    )


# ---------------------------------------------------------------------------
# backup_restore_targets —— 备份目标过滤
# ---------------------------------------------------------------------------


def test_backup_restore_targets_filters_no_key(monkeypatch):
    """只保留配置了 API key 的环境（无全局 key 时，未覆盖的环境被剔除）。"""
    monkeypatch.delenv("TEST_API_KEY", raising=False)
    monkeypatch.setenv("TEST_API_KEY_10_0_0_122", "glpat-inner")
    targets = backup_restore.backup_restore_targets(
        ["https://a.example.com:507", "http://10.0.0.122:8080"]
    )
    assert targets == [("http://10.0.0.122:8080", "glpat-inner")]


def test_backup_restore_targets_global_key_applies_all(monkeypatch):
    """只有全局 key 时，所有环境都受保护。"""
    monkeypatch.setenv("TEST_API_KEY", "glpat-global")
    monkeypatch.delenv("TEST_API_KEY_10_0_0_122", raising=False)
    targets = backup_restore.backup_restore_targets(
        ["http://10.0.0.122:8080", "https://home.chenkaidi.top:507"]
    )
    assert len(targets) == 2
    assert all(key == "glpat-global" for _, key in targets)


def test_backup_restore_targets_all_missing(monkeypatch):
    """全部环境都无 API key 时返回空列表（调用方据此降级为不保护）。"""
    monkeypatch.delenv("TEST_API_KEY", raising=False)
    assert backup_restore.backup_restore_targets(
        ["http://10.0.0.122:8080", "https://home.chenkaidi.top:507"]
    ) == []


def test_backup_restore_targets_empty_input(monkeypatch):
    """空输入返回空列表。"""
    monkeypatch.setenv("TEST_API_KEY", "glpat-global")
    assert backup_restore.backup_restore_targets([]) == []


# ---------------------------------------------------------------------------
# create_backup —— 创建备份
# ---------------------------------------------------------------------------


def test_create_backup_success_returns_filename():
    """POST /backups 返回 201 + filename，解析出文件名。"""
    with mock.patch.object(
        backup_restore, "_request_json", return_value=(201, {"filename": "backup_20260810_180000.tar.gz.enc"})
    ) as req:
        name = backup_restore.create_backup("https://home.chenkaidi.top:507", "glpat-x")
        assert name == "backup_20260810_180000.tar.gz.enc"
        # 断言请求细节：正确 URL、POST 方法、X-API-Key 头
        method, url, kwargs = req.call_args[0][0], req.call_args[0][1], req.call_args[1]
        assert url == "https://home.chenkaidi.top:507/backups"
        assert method == "POST"
        assert kwargs.get("api_key") == "glpat-x"


def test_create_backup_strips_trailing_slash():
    """base_url 末尾带 / 时拼接不产生双斜杠。"""
    with mock.patch.object(
        backup_restore, "_request_json", return_value=(201, {"filename": "backup_20260810_180000.tar.gz.enc"})
    ) as req:
        backup_restore.create_backup("http://10.0.0.122:8080/", "glpat-x")
        assert req.call_args[0][1] == "http://10.0.0.122:8080/backups"


def test_create_backup_missing_filename_raises():
    """响应缺少 filename 字段视为失败（调用方需要文件名才能恢复）。"""
    with mock.patch.object(backup_restore, "_request_json", return_value=(200, {"size": 1})):
        with pytest.raises(RuntimeError, match="filename"):
            backup_restore.create_backup("https://home.chenkaidi.top:507", "glpat-x")


def test_create_backup_http_error_passthrough():
    """后端返回错误（401 无权限等）时异常透传，不静默吞掉。"""
    with mock.patch.object(
        backup_restore, "_request_json",
        side_effect=RuntimeError("401 Unauthorized: Invalid API Key"),
    ):
        with pytest.raises(RuntimeError, match="401"):
            backup_restore.create_backup("https://home.chenkaidi.top:507", "bad-key")


# ---------------------------------------------------------------------------
# restore_backup —— 恢复备份
# ---------------------------------------------------------------------------


def test_restore_backup_url_and_confirm():
    """恢复请求带 confirm=true 与文件名路径。"""
    with mock.patch.object(backup_restore, "_request_json", return_value=(200, {"ok": True})) as req:
        backup_restore.restore_backup("http://10.0.0.122:8080", "glpat-x", "backup_20260810_180000.tar.gz.enc")
        method, url, kwargs = req.call_args[0][0], req.call_args[0][1], req.call_args[1]
        assert method == "POST"
        assert url == (
            "http://10.0.0.122:8080/backups/backup_20260810_180000.tar.gz.enc/restore?confirm=true"
        )
        assert kwargs.get("api_key") == "glpat-x"


def test_restore_backup_invalid_filename_raises():
    """非法文件名（路径穿越/不符合命名规范）必须被客户端拒绝。"""
    for bad in ("../keys.db", "keys.db", "backup_x.tar.gz.enc", "", "a/b/backup_20260810.tar.gz.enc"):
        with pytest.raises(ValueError, match="非法备份文件名"):
            backup_restore.restore_backup(
                "http://10.0.0.122:8080", "glpat-x", bad
            )


def test_restore_backup_http_error_passthrough():
    """恢复失败（如备份不存在 404）时异常透传。"""
    with mock.patch.object(
        backup_restore, "_request_json",
        side_effect=RuntimeError("404 Not Found: 备份不存在"),
    ):
        with pytest.raises(RuntimeError, match="404"):
            backup_restore.restore_backup(
                "http://10.0.0.122:8080", "glpat-x", "backup_20260810_180000.tar.gz.enc"
            )


# ---------------------------------------------------------------------------
# _is_backup_name —— 备份文件名合法性校验
# ---------------------------------------------------------------------------


def test_is_backup_name_valid():
    """符合命名规范（backup_YYYYMMDD_HHMMSS[._pre_restore].tar.gz.enc）的文件名通过。"""
    assert backup_restore._is_backup_name("backup_20260810_180000.tar.gz.enc")
    assert backup_restore._is_backup_name("backup_20260810_180000_pre_restore.tar.gz.enc")


def test_is_backup_name_invalid():
    """路径穿越、扩展名不符、日期格式错误等一律拒绝。"""
    for bad in (
        "../keys.db",
        "keys.db",
        "backup.tar.gz.enc",
        "backup_20260810.tar.gz.enc",
        "backup_20260810_180000.tar.gz",
        "backup_20260810_180000.enc",
        "backup_2026081_180000.tar.gz.enc",  # 日期只有 7 位
    ):
        assert not backup_restore._is_backup_name(bad)


# ---------------------------------------------------------------------------
# wait_backend_alive —— 恢复后服务重启等待
# ---------------------------------------------------------------------------


def test_wait_backend_alive_immediate():
    """第一次探测即成功返回 True。"""
    with mock.patch.object(backup_restore, "_backend_reachable", return_value=True) as reach:
        assert backup_restore.wait_backend_alive("http://10.0.0.122:8080", timeout=10) is True
        assert reach.call_count == 1


def test_wait_backend_alive_eventually(monkeypatch):
    """前几次探测失败（服务重启中），随后成功，返回 True。"""
    import time
    monkeypatch.setattr(time, "sleep", lambda s: None)  # 不真的等待
    side_effect = [False, False, True]
    with mock.patch.object(backup_restore, "_backend_reachable", side_effect=side_effect):
        assert backup_restore.wait_backend_alive("http://10.0.0.122:8080", timeout=10) is True


def test_wait_backend_alive_timeout(monkeypatch):
    """超时前一直不可达，返回 False（不抛异常，由调用方决定后续动作）。"""
    import time
    monkeypatch.setattr(time, "sleep", lambda s: None)
    with mock.patch.object(backup_restore, "_backend_reachable", return_value=False):
        assert backup_restore.wait_backend_alive("http://10.0.0.122:8080", timeout=5) is False


def test_wait_backend_alive_zero_timeout():
    """timeout=0 时不做任何探测立即返回 False。"""
    with mock.patch.object(backup_restore, "_backend_reachable") as reach:
        assert backup_restore.wait_backend_alive("http://10.0.0.122:8080", timeout=0) is False
        reach.assert_not_called()
