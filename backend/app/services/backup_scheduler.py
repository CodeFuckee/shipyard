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
"""

from datetime import datetime, timedelta
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


def start_backup_scheduler() -> None:
    """后台守护线程主循环：按 BACKUP_CRON 定时触发备份并执行旧备份清理。

    每 30 秒检查一次当前分钟是否命中；命中则执行备份 + 清理。
    与 docker_event_listener 相同，以 daemon 线程方式在 lifespan 中启动。
    """
    import time

    from app.core.config import BACKUP_CRON, BACKUP_KEEP_DAYS
    from app.services import backup_service

    if not BACKUP_CRON:
        return
    schedule = CronSchedule(BACKUP_CRON)
    last_fired_minute: Optional[str] = None
    while True:
        now = datetime.now()
        minute_key = now.strftime("%Y%m%d%H%M")
        if schedule.matches(now) and minute_key != last_fired_minute:
            last_fired_minute = minute_key
            try:
                backup_service.create_backup()
                removed = backup_service.cleanup_old_backups(BACKUP_KEEP_DAYS)
                print(
                    f"[backup] 定时备份完成: {now.strftime('%Y-%m-%d %H:%M:%S')}，"
                    f"清理旧备份 {removed} 个"
                )
            except Exception as e:  # 定时任务失败不能拖垮主进程
                print(f"[backup] 定时备份失败: {e}")
        time.sleep(30)
