from fastapi import APIRouter, Depends, HTTPException
from typing import List, Dict, Any
import docker
import os
from app.core.security import get_api_key
from app.core.utils import get_docker_client
from app.core.config import HOST_FILESYSTEM_ROOT

router = APIRouter(
    prefix="/volumes",
    tags=["volumes"],
    dependencies=[Depends(get_api_key)]
)

@router.get("", response_model=List[Dict[str, Any]])
async def list_volumes():
    """
    Get a list of all Docker volumes.
    """
    client = get_docker_client()
    try:
        volumes = client.volumes.list()
        
        # Check usage
        containers = client.containers.list(all=True)
        used_volume_names = set()
        for c in containers:
            mounts = c.attrs.get("Mounts", [])
            for m in mounts:
                if m.get("Type") == "volume":
                    name = m.get("Name")
                    if name:
                        used_volume_names.add(name)

        result = []
        for vol in volumes:
            result.append({
                "id": vol.id,
                "name": vol.name,
                "driver": vol.attrs.get("Driver"),
                "created": vol.attrs.get("CreatedAt"),
                "mountpoint": vol.attrs.get("Mountpoint"),
                "labels": vol.attrs.get("Labels"),
                "in_use": vol.name in used_volume_names
            })
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error retrieving volumes: {str(e)}")
    finally:
        client.close()

@router.delete("/{volume_id}", response_model=Dict[str, Any])
async def delete_volume(volume_id: str, force: bool = False):
    """
    Delete a specific Docker volume.
    """
    client = get_docker_client()
    try:
        volume = client.volumes.get(volume_id)
        volume.remove(force=force)
        return {"status": "success", "message": f"Volume {volume_id} deleted successfully"}
    except docker.errors.NotFound:
        raise HTTPException(status_code=404, detail="Volume not found")
    except docker.errors.APIError as e:
        if "volume is in use" in str(e).lower():
             raise HTTPException(status_code=409, detail=f"Volume is in use: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Docker API Error: {str(e)}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error deleting volume: {str(e)}")
    finally:
        client.close()


@router.get("/{volume_id}", response_model=Dict[str, Any])
async def get_volume_details(volume_id: str):
    """
    Get detailed information about a specific Docker volume.
    """
    client = get_docker_client()
    try:
        volume = client.volumes.get(volume_id)
        
        # Check if volume is in use
        containers = client.containers.list(all=True)
        used_by = []
        for c in containers:
            mounts = c.attrs.get("Mounts", [])
            for m in mounts:
                if m.get("Type") == "volume" and m.get("Name") == volume.name:
                    used_by.append(c.name)
                    break
        
        data = dict(volume.attrs)
        data["in_use"] = len(used_by) > 0
        data["used_by_containers"] = used_by
        return data
    except docker.errors.NotFound:
        raise HTTPException(status_code=404, detail="Volume not found")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error retrieving volume details: {str(e)}")
    finally:
        client.close()

@router.get("/{volume_id}/files", response_model=List[Dict[str, Any]])
async def get_volume_files(volume_id: str, path: str = ""):
    """
    Get list of files and directories in a volume.
    path: Relative path inside the volume (e.g., 'subdir/').
    """
    client = get_docker_client()
    try:
        volume = client.volumes.get(volume_id)
        mountpoint = volume.attrs.get("Mountpoint")
        
        if not mountpoint:
            # Some drivers might not expose Mountpoint or it might be null
            raise HTTPException(status_code=400, detail="Volume mountpoint not found or not accessible directly")

        # Construct path to access via host mount
        # HOST_FILESYSTEM_ROOT defaults to /hostfs
        # mountpoint is absolute path on host, e.g. /var/lib/docker/volumes/myvol/_data
        
        clean_mountpoint = mountpoint.lstrip("/")
        base_path = os.path.join(HOST_FILESYSTEM_ROOT, clean_mountpoint)
        
        # Handle requested sub-path
        clean_path = path.lstrip("/")
        target_path = os.path.join(base_path, clean_path)
        
        # Resolve paths to absolute paths to prevent traversal
        abs_base = os.path.abspath(base_path)
        abs_target = os.path.abspath(target_path)
        
        if not abs_target.startswith(abs_base):
            raise HTTPException(status_code=403, detail="Access denied: Path traversal detected")
            
        if not os.path.exists(abs_target):
            raise HTTPException(status_code=404, detail="Path not found")
            
        if not os.path.isdir(abs_target):
            raise HTTPException(status_code=400, detail="Path is not a directory")
            
        items = []
        with os.scandir(abs_target) as it:
            for entry in it:
                try:
                    stat = entry.stat()
                    items.append({
                        "name": entry.name,
                        "type": "directory" if entry.is_dir() else "file",
                        "size": stat.st_size,
                        "modified": stat.st_mtime,
                        "is_symlink": entry.is_symlink()
                    })
                except OSError:
                    continue # Skip entries we cannot access
        
        return items

    except docker.errors.NotFound:
        raise HTTPException(status_code=404, detail="Volume not found")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error listing files: {str(e)}")
    finally:
        client.close()
