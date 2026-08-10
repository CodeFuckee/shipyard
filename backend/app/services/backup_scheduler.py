"""定时备份调度 —— 自实现轻量 cron 解析（无第三方依赖）。

支持标准 5 段 cron 表达式（分 时 日 月 周）：
    *        任意值
    */n      步长（如 */5 = 每 5）
    a-b      范围
    a,b      列表（可混合 a-b、*/n）
    具体值   如 30、3

字段取值范围（与 cron 惯例一致）：
    分 0-59  时 0-23  日 1-31  月 1-12  周 0-6（0=周日）
周字段按 cron 惯例 0=周日，内部转换为 Python weekday()（周一=0）。

典型用法（配合后台守护线程）：
    sched = CronSchedule(BACKUP_CRON)
    while True:
        if sched.matches(datetime.now()):
            ...
        time.sleep(30)

调度配置持久化：
- 默认值来自环境变量 BACKUP_CRON / BACKUP_KEEP_DAYS
- Web UI 修改后保存到配置文件（BACKUP_SCHEDULE_FILE，默认 data/backup_schedule.json），
  配置文件存在时优先于环境变量；调度线程每次循环重新加载，修改立即生效。
"""

import json
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional, Set

# 每段取值范围：分 时 日 月 周
_FIELD_RANGES = [(0, 59), (0, 23), (1, 31), (1, 12), (0, 6)]
# 日/周字段的全匹配集合（用于判断表达式是否为 `*`）
_ALL_DAYS = set(range(1, 32))
_ALL_WEEKDAYS = set(range(0, 7))
# 扫描 next_fire 时的最大步数（避免非法组合死循环，一年约 52 万分钟）
_MAX_SCAN_MINUTES = 366 * 24 * 60


def _parse_item(item: str, lo: int, hi: int) -> Set[int]:
    """解析单个逗号分隔项（如 `*`、`*/5`、`1-5`、`30`），返回值集合。"""
    item = item.strip()
    if item == "*":
        return set(range(lo, hi + 1))

    step = 1
    base = item
    if "/" in item:
        base, _, step_str = item.partition("/")
        if not step_str.isdigit() or int(step_str) <= 0:
            raise ValueError(f"非法 cron 步长: {item!r}")
        step = int(step_str)
        if base == "*":
            return set(range(lo, hi + 1, step))

    if "-" in base:
        start_str, _, end_str = base.partition("-")
        if not start_str.isdigit() or not end_str.isdigit():
            raise ValueError(f"非法 cron 范围: {item!r}")
        start, end = int(start_str), int(end_str)
        if start < lo or end > hi or start > end:
            raise ValueError(f"cron 范围越界: {item!r}（范围 {lo}-{hi}）")
        return set(range(start, end + 1, step))

    if not base.isdigit():
        raise ValueError(f"非法 cron 字段: {item!r}")
    value = int(base)
    if value < lo or value > hi:
        raise ValueError(f"cron 值越界: {value}（范围 {lo}-{hi}）")
    return {value}


def _parse_field(field: str, lo: int, hi: int, name: str) -> Set[int]:
    """解析整段（逗号分隔），空项报错。"""
    parts = [p for p in field.split(",")]
    if not parts or any(p.strip() == "" for p in parts):
        raise ValueError(f"cron {name} 字段为空项: {field!r}")
    values: Set[int] = set()
    for item in parts:
        values |= _parse_item(item, lo, hi)
    return values


def _to_cron_weekday(dt: datetime) -> int:
    """Python weekday()（周一=0）→ cron 周字段（周日=0）。"""
    return (dt.weekday() + 1) % 7


class CronSchedule:
    """标准 5 段 cron 表达式解析与匹配。"""

    def __init__(self, expr: str):
        self.expr = expr
        fields = expr.split()
        if len(fields) != 5:
            raise ValueError(
                f"cron 表达式必须为 5 段（分 时 日 月 周），实际 {len(fields)} 段: {expr!r}"
            )
        self.minutes = _parse_field(fields[0], *_FIELD_RANGES[0], "分")
        self.hours = _parse_field(fields[1], *_FIELD_RANGES[1], "时")
        self.days = _parse_field(fields[2], *_FIELD_RANGES[2], "日")
        self.months = _parse_field(fields[3], *_FIELD_RANGES[3], "月")
        self.weekdays = _parse_field(fields[4], *_FIELD_RANGES[4], "周")

    def matches(self, dt: datetime) -> bool:
        """dt 时刻是否命中 cron 表达式。

        日/周字段按标准 cron（Vixie）语义：
        - 两者均为 *：任意日匹配
        - 仅日指定：按日匹配
        - 仅周指定：按周匹配
        - 两者都指定：日或周任一匹配即命中
        """
        day_match = dt.day in self.days
        weekday_match = _to_cron_weekday(dt) in self.weekdays

        days_any = self.days == _ALL_DAYS
        weekdays_any = self.weekdays == _ALL_WEEKDAYS

        if days_any and weekdays_any:
            day_ok = True
        elif not days_any and not weekdays_any:
            day_ok = day_match or weekday_match
        elif not days_any:
            day_ok = day_match
        else:
            day_ok = weekday_match

        return (
            dt.minute in self.minutes
            and dt.hour in self.hours
            and dt.month in self.months
            and day_ok
        )

    def next_fire(self, after: datetime) -> Optional[datetime]:
        """返回严格晚于 after 的下一个触发时刻；表达式永不触发时返回 None。"""
        candidate = after + timedelta(minutes=1) - timedelta(
            seconds=after.second, microseconds=after.microsecond
        )
        for _ in range(_MAX_SCAN_MINUTES):
            if self.matches(candidate):
                return candidate
            candidate += timedelta(minutes=1)
        return None


# ---------------------------------------------------------------------------
# 调度配置持久化
# ---------------------------------------------------------------------------

# 配置文件最大允许字节数（防御异常大文件拖慢读取）
_SCHEDULE_FILE_MAX_BYTES = 64 * 1024


def get_schedule_file() -> Path:
    """调度配置文件路径（测试隔离点）。"""
    from app.core.config import BACKUP_SCHEDULE_FILE

    return Path(BACKUP_SCHEDULE_FILE)


def _default_schedule() -> dict:
    """环境变量默认配置（无配置文件时的回退值）。"""
    from app.core.config import BACKUP_CRON, BACKUP_KEEP_DAYS

    cron = (BACKUP_CRON or "").strip()
    return {"enabled": bool(cron), "cron": cron, "keep_days": BACKUP_KEEP_DAYS}


def _validate_schedule(enabled: bool, cron: str, keep_days) -> None:
    """校验调度配置；非法时抛 ValueError。"""
    if not isinstance(keep_days, int) or isinstance(keep_days, bool):
        raise ValueError(f"keep_days 必须为 1~365 的整数: {keep_days!r}")
    if keep_days < 1 or keep_days > 365:
        raise ValueError(f"keep_days 必须在 1~365 之间: {keep_days!r}")
    if not enabled:
        return  # 禁用时 cron 允许为空
    if not cron:
        raise ValueError("启用定时备份时 cron 表达式不能为空")
    try:
        CronSchedule(cron)
    except ValueError as e:
        raise ValueError(f"非法 cron 表达式: {e}") from e


def _load_schedule_file() -> Optional[dict]:
    """读取配置文件；缺失/损坏/缺字段时返回 None（调用方回退环境变量默认值）。"""
    path = get_schedule_file()
    try:
        if not path.exists() or path.stat().st_size > _SCHEDULE_FILE_MAX_BYTES:
            return None
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else None
    except (OSError, ValueError, json.JSONDecodeError):
        return None


def _compute_next_fire(enabled: bool, cron: str) -> Optional[str]:
    """计算下次触发时间（enabled=False 或 cron 空 → None）。"""
    if not enabled or not cron:
        return None
    try:
        next_fire = CronSchedule(cron).next_fire(datetime.now())
    except ValueError:
        return None
    return next_fire.strftime("%Y%m%d%H%M%S") if next_fire else None


def get_schedule_config() -> dict:
    """当前生效的调度配置：配置文件优先，否则环境变量默认值。

    返回 {enabled, cron, keep_days, next_fire}。
    配置文件损坏/缺失字段时逐项回退，保证调度线程不会因配置异常崩溃。
    """
    default = _default_schedule()
    file_data = _load_schedule_file()
    if file_data is None:
        cfg = {"enabled": default["enabled"], "cron": default["cron"], "keep_days": default["keep_days"]}
    else:
        enabled = bool(file_data.get("enabled", False))
        cron = str(file_data.get("cron", "") or "").strip()
        # enabled=True 但 cron 缺失/非法 → 降级为禁用，避免调度器崩溃
        if enabled and not cron:
            enabled = False
        if enabled:
            try:
                CronSchedule(cron)
            except ValueError:
                enabled = False
                cron = ""
        elif cron:
            cron = ""
        keep_days = file_data.get("keep_days", default["keep_days"])
        if not isinstance(keep_days, int) or isinstance(keep_days, bool):
            keep_days = default["keep_days"]
        else:
            keep_days = max(1, min(365, keep_days))
        cfg = {"enabled": enabled, "cron": cron, "keep_days": keep_days}
    cfg["next_fire"] = _compute_next_fire(cfg["enabled"], cfg["cron"])
    return cfg


def save_schedule_config(enabled: bool, cron: str, keep_days: int) -> dict:
    """校验并持久化调度配置，返回更新后的配置（含 next_fire）。

    写入配置文件后立即对调度线程生效（线程每次循环重新加载）。
    """
    cron = (cron or "").strip()
    _validate_schedule(enabled, cron, keep_days)
    path = get_schedule_file()
    path.parent.mkdir(parents=True, exist_ok=True)
    data = {"enabled": bool(enabled), "cron": cron, "keep_days": int(keep_days)}
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    result = dict(data)
    result["next_fire"] = _compute_next_fire(enabled, cron)
    return result


def start_backup_scheduler() -> None:
    """后台守护线程主循环：按调度配置定时触发备份并执行旧备份清理。

    配置来源：配置文件（BACKUP_SCHEDULE_FILE，优先）→ 环境变量 BACKUP_CRON /
    BACKUP_KEEP_DAYS。每次循环重新加载配置，Web UI 修改后立即生效，无需重启。
    每 30 秒检查一次当前分钟是否命中；命中则执行备份 + 清理。
    与 docker_event_listener 相同，以 daemon 线程方式在 lifespan 中启动。
    """
    import time

    from app.services import backup_service

    last_fired_minute: Optional[str] = None
    while True:
        cfg = get_schedule_config()
        if cfg["enabled"] and cfg["cron"]:
            schedule = CronSchedule(cfg["cron"])
            keep_days = cfg["keep_days"]
        else:
            schedule = None
            keep_days = 0
        now = datetime.now()
        if schedule is not None:
            minute_key = now.strftime("%Y%m%d%H%M")
            if schedule.matches(now) and minute_key != last_fired_minute:
                last_fired_minute = minute_key
                try:
                    backup_service.create_backup()
                    removed = backup_service.cleanup_old_backups(keep_days)
                    print(
                        f"[backup] 定时备份完成: {now.strftime('%Y-%m-%d %H:%M:%S')}，"
                        f"清理旧备份 {removed} 个"
                    )
                except Exception as e:  # 定时任务失败不能拖垮主进程
                    print(f"[backup] 定时备份失败: {e}")
        time.sleep(30)
