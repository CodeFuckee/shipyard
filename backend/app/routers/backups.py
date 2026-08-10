"""备份与恢复 REST 端点。

认证：X-API-Key（与 admin 等管理端点一致）。
端点：
    POST   /backups                        手动创建备份
    GET    /backups                        备份列表（按时间倒序）
    GET    /backups/{filename}/download    下载备份文件（加密 tar.gz）
    DELETE /backups/{filename}             手动删除备份
    POST   /backups/{filename}/restore     恢复备份（覆盖现有数据，需 confirm=true）
    GET    /backups/schedule               查询定时备份配置
    PUT    /backups/schedule               更新定时备份配置（立即生效）
"""

from typing import List

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel

from app.core.security import get_api_key
from app.services import backup_scheduler, backup_service

router = APIRouter(
    prefix="/backups", tags=["backups"], dependencies=[Depends(get_api_key)]
)


def _not_found(e: FileNotFoundError) -> HTTPException:
    return HTTPException(status_code=404, detail=str(e))


class ScheduleUpdate(BaseModel):
    """定时备份配置更新请求体。"""

    enabled: bool
    cron: str
    keep_days: int


@router.post("", status_code=201, summary="手动创建备份")
def create_backup() -> dict:
    """立即创建一次备份（加密 tar.gz），返回备份文件名/大小/时间。"""
    try:
        return backup_service.create_backup()
    except FileNotFoundError as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@router.get("", summary="备份列表")
def list_backups() -> List[dict]:
    """列出备份目录中的所有备份（按时间倒序）。"""
    return backup_service.list_backups()


@router.get("/schedule", summary="查询定时备份配置")
def get_schedule() -> dict:
    """返回当前定时备份配置（enabled/cron/keep_days/next_fire）。"""
    return backup_scheduler.get_schedule_config()


@router.put("/schedule", summary="更新定时备份配置（立即生效）")
def update_schedule(payload: ScheduleUpdate) -> dict:
    """更新定时备份配置。

    写入配置文件，调度线程下次循环即按新配置执行，无需重启。
    校验失败（非法 cron、keep_days 越界等）返回 400，现有配置不受影响。
    """
    try:
        return backup_scheduler.save_schedule_config(
            enabled=payload.enabled,
            cron=payload.cron,
            keep_days=payload.keep_days,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e


@router.get("/{filename}/download", summary="下载备份文件")
def download_backup(filename: str) -> FileResponse:
    """下载指定备份文件（加密 tar.gz）。

    仅接受符合命名规范的备份文件名（防路径穿越/误下载非备份文件）。
    """
    # 与 restore/delete 相同的命名校验：非法名视为请求错误
    if not backup_service._is_backup_name(filename):
        raise HTTPException(status_code=400, detail="非法备份文件名")
    path = backup_service.get_backup_dir() / filename
    if not path.exists():
        raise HTTPException(status_code=404, detail=f"备份不存在: {filename}")
    return FileResponse(path, media_type="application/gzip", filename=filename)


@router.delete("/{filename}", summary="手动删除备份")
def delete_backup(filename: str) -> dict:
    """删除指定备份文件。"""
    try:
        backup_service.delete_backup(filename)
    except FileNotFoundError as e:
        raise _not_found(e) from e
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    return {"ok": True, "deleted": filename}


@router.post("/{filename}/restore", summary="恢复备份（覆盖现有数据）")
def restore_backup(filename: str, confirm: bool = False) -> dict:
    """从备份恢复数据库。

    危险操作：会覆盖当前数据库并触发服务重启。
    必须携带 confirm=true 才会执行；恢复前自动生成 pre_restore 快照。
    """
    try:
        return backup_service.restore_backup(filename, confirm=confirm)
    except FileNotFoundError as e:
        raise _not_found(e) from e
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except Exception as e:
        # 解密/校验/完整性失败等均视为请求错误，原库不受影响
        raise HTTPException(status_code=400, detail=str(e)) from e
