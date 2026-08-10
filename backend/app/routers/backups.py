"""备份与恢复 REST 端点。

认证：X-API-Key（与 admin 等管理端点一致）。
端点：
    POST   /backups                        手动创建备份
    GET    /backups                        备份列表（按时间倒序）
    DELETE /backups/{filename}             手动删除备份
    POST   /backups/{filename}/restore     恢复备份（覆盖现有数据，需 confirm=true）
"""

from typing import List

from fastapi import APIRouter, Depends, HTTPException

from app.core.security import get_api_key
from app.services import backup_service

router = APIRouter(
    prefix="/backups", tags=["backups"], dependencies=[Depends(get_api_key)]
)


def _not_found(e: FileNotFoundError) -> HTTPException:
    return HTTPException(status_code=404, detail=str(e))


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
