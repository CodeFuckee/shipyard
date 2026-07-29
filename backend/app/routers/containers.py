from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse, StreamingResponse
from typing import Dict, Any, List, Optional, Union
import docker
import os
import tarfile
import io
import time
from pydantic import BaseModel
from app.core.security import get_api_key
from app.core.utils import (
    get_docker_client,
    get_current_container_id,
    process_container_summary,
    parse_docker_run_command,
)
from app.core.config import HOST_FILESYSTEM_ROOT

router = APIRouter(
    prefix="/containers", tags=["containers"], dependencies=[Depends(get_api_key)]
)


class DockerRunRequest(BaseModel):
    command: str


class FileUpdateRequest(BaseModel):
    path: str
    content: str


@router.get("", response_model=List[Dict[str, Any]])
async def list_containers():
    """
    Get information about all Docker containers.
    """
    client = get_docker_client()
    try:
        containers = client.containers.list(all=True)
        result = []
        for container in containers:
            container_info = {
                "id": container.id,
                "short_id": container.short_id,
                "name": container.name,
                "status": str(container.status).lower(),
                "image": str(container.image),
                "attrs": container.attrs,
            }
            result.append(container_info)
        return result
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Error retrieving containers: {str(e)}"
        )
    finally:
        client.close()


@router.get("/{container_id}/download")
async def download_container_file(container_id: str, path: str):
    """
    Download a file from the container.
    If the file is mounted, it downloads directly from the host.
    If not mounted, it downloads as a tar archive.
    """
    if not path or not path.startswith("/"):
        raise HTTPException(
            status_code=400, detail="Path must be absolute (e.g., /data/config.json)"
        )

    client = get_docker_client()
    try:
        container = client.containers.get(container_id)
        mounts = container.attrs.get("Mounts", [])

        # Find the best matching mount (longest prefix)
        path_clean = path.rstrip("/")
        best_match = None

        for mount in mounts:
            dest = mount.get("Destination")
            if not dest:
                continue

            dest_clean = dest.rstrip("/")

            if path_clean == dest_clean or path_clean.startswith(dest_clean + "/"):
                if best_match is None or len(dest_clean) > len(
                    best_match.get("Destination").rstrip("/")
                ):
                    best_match = mount

        if best_match:
            mount_source = best_match.get("Source")
            mount_dest = best_match.get("Destination")
            mount_dest_clean = mount_dest.rstrip("/")

            if path_clean == mount_dest_clean:
                relative_path = ""
                host_abs_path = mount_source
            else:
                relative_path = path_clean[len(mount_dest_clean) :].lstrip("/")
                host_abs_path = os.path.join(mount_source, relative_path)

            clean_host_abs_path = host_abs_path.lstrip("/")
            final_path = os.path.join(HOST_FILESYSTEM_ROOT, clean_host_abs_path)

            # Security checks
            if ".." in relative_path.split("/"):
                raise HTTPException(status_code=403, detail="Path traversal detected")

            if os.path.exists(final_path):
                if os.path.isdir(final_path):
                    raise HTTPException(
                        status_code=400,
                        detail="Cannot download directory directly. Please specify a file.",
                    )
                return FileResponse(final_path, filename=os.path.basename(path))

        # Fallback for non-mounted files: use get_archive
        try:
            stream, stat = container.get_archive(path)
            # stat contains: name, size, mode, mtime, linkname, uname, gname, uis, gid
            return StreamingResponse(
                stream,
                media_type="application/x-tar",
                headers={
                    "Content-Disposition": f'attachment; filename="{os.path.basename(path)}.tar"'
                },
            )
        except docker.errors.NotFound:
            raise HTTPException(
                status_code=404, detail="File not found inside container"
            )
        except Exception as e:
            raise HTTPException(
                status_code=500,
                detail=f"Error retrieving file from container: {str(e)}",
            )

    except docker.errors.NotFound:
        raise HTTPException(status_code=404, detail="Container not found")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error: {str(e)}")
    finally:
        client.close()


@router.get("/summary", response_model=List[Dict[str, Any]])
async def list_containers_summary():
    """
    Get summary information (id, name, status, stack, image, ports, is_self) of all Docker containers.
    """
    client = get_docker_client()
    self_id = get_current_container_id()
    try:
        containers = client.containers.list(all=True)
        result = [process_container_summary(c, self_id) for c in containers]
        return result
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Error retrieving containers summary: {str(e)}"
        )
    finally:
        client.close()


@router.post("/run", response_model=Dict[str, Any])
async def run_container(request: DockerRunRequest):
    """
    Run a container using a docker run command string.
    Example: {"command": "docker run -d -p 8080:80 --name my-nginx nginx"}
    """
    client = get_docker_client()
    try:
        params = parse_docker_run_command(request.command)

        # Pull image if not exists? Or docker-py run handles it?
        # docker-py run(..., detach=True) is equivalent to `docker run -d`
        # It will try to pull image if missing usually, but explicit pull is safer/clearer?
        # client.containers.run docs say it pulls if missing.

        # If detach=False (default is False in our parser if -d not present), run() waits for command to finish and returns logs (bytes)
        # But for API, we probably always want to return container info, so maybe force detach=True if not specified?
        # Or if user didn't specify -d, run() returns logs.
        # But this is an HTTP API, blocking for a long process is bad.
        # However, user expectation of "docker run" without -d is interactive/logs.
        # Given this is a management API, we should probably enforce detach=True OR handle the output.
        # BUT, if we return container object, it means it ran detached.
        # If we didn't pass detach=True, `client.containers.run` returns logs (bytes) or raises error.

        # Let's adjust logic:
        # If -d is NOT present, we still might want to run it?
        # If we run attached, this API call will block until container finishes.
        # If container is a long running server, this will timeout.
        # So we should probably Force detach=True unless user explicitly knows what they are doing.
        # But let's respect the parsed args. If user forgets -d, it might block.
        # Let's default detach to True if not specified?
        # No, let's respect the flag but warn/handle.
        # Actually, if detach is False, `container` variable will hold the logs (bytes).

        if not params.get("detach"):
            # If not detached, run() returns output.
            # We can't return a container object in this case easily unless we catch it.
            # But wait, client.containers.run(..., detach=False) starts the container, waits for it to finish, and returns logs.
            # This is dangerous for a web API.
            # Recommendation: Always force detach=True for this API?
            # User asked for "docker run form command".
            # If I force detach, I change semantics.
            # But blocking the thread is worse.
            # I will set detach=True if not specified, and maybe add a warning or note.
            # Or better: Check if params['detach'] is True. If not, set it to True and tell user "Running in detached mode".
            pass

        # For safety in this context, let's force detach=True if not specified to avoid blocking the server.
        if not params.get("detach"):
            params["detach"] = True

        container = client.containers.run(**params)

        return {
            "status": "success",
            "id": container.id,
            "short_id": container.short_id,
            "name": container.name,
            "warnings": ["Forced detached mode (run -d) to avoid blocking API"]
            if not request.command.find("-d") != -1
            and not request.command.find("--detach") != -1
            else [],
        }

    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Invalid command: {str(e)}")
    except docker.errors.ImageNotFound:
        raise HTTPException(
            status_code=404, detail=f"Image not found: {params.get('image')}"
        )
    except docker.errors.APIError as e:
        raise HTTPException(status_code=500, detail=f"Docker API Error: {str(e)}")
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Error running container: {str(e)}"
        )
    finally:
        client.close()


@router.get("/{container_id}/logs")
async def get_container_logs(container_id: str, tail: int = 2000):
    """
    Get logs for a specific container.
    Defaults to last 2000 lines.
    """
    client = get_docker_client()
    try:
        container = client.containers.get(container_id)
        # logs() returns bytes, so we need to decode it
        logs = container.logs(tail=tail, timestamps=True).decode(
            "utf-8", errors="replace"
        )
        return {"logs": logs}
    except docker.errors.NotFound:
        raise HTTPException(status_code=404, detail="Container not found")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error retrieving logs: {str(e)}")
    finally:
        client.close()


import re
from datetime import datetime


async def list_files_via_exec(
    container, path: str, mounts: List[Dict[str, Any]] = []
) -> Union[List[Dict[str, Any]], Dict[str, Any]]:
    """
    List files using `docker exec` when path is not mounted.
    If path is a file, returns its content.
    If path is a directory, returns list of files.
    """
    # Check if path is a directory first
    check_dir_cmd = f"test -d '{path}'"
    exit_code, _ = container.exec_run(["/bin/sh", "-c", check_dir_cmd])
    is_dir = exit_code == 0

    # If it's not a directory, check if it's a file and read content
    if not is_dir:
        # Verify it exists as a file
        check_file_cmd = f"test -f '{path}'"
        exit_code, _ = container.exec_run(["/bin/sh", "-c", check_file_cmd])
        if exit_code == 0:
            # It's a file, read content
            # Limit size to 1MB to prevent issues
            size_cmd = f"stat -c %s '{path}'"
            size_res = container.exec_run(["/bin/sh", "-c", size_cmd])
            if size_res.exit_code == 0:
                try:
                    size = int(size_res.output.decode("utf-8").strip())
                    if size > 1024 * 1024:
                        raise HTTPException(
                            status_code=400, detail="File too large to view (max 1MB)"
                        )
                except ValueError:
                    pass  # Ignore if stat fails, proceed to try reading

            cat_cmd = f"cat '{path}'"
            exec_result = container.exec_run(["/bin/sh", "-c", cat_cmd])

            if exec_result.exit_code != 0:
                raise HTTPException(
                    status_code=500,
                    detail=f"Error reading file: {exec_result.output.decode('utf-8')}",
                )

            try:
                content = exec_result.output.decode("utf-8")
                return {"content": content}
            except UnicodeDecodeError:
                raise HTTPException(status_code=400, detail="Binary file not supported")

        # If neither dir nor file (or stat failed but ls might work?) - fall through to ls/stat logic below which handles error

    # Prepare mount points for checking if an item is a mount root
    mount_destinations = set()
    for m in mounts:
        dest = m.get("Destination")
        if dest:
            mount_destinations.add(dest.rstrip("/"))

    # 1. Try `stat` command (works on most Linux distros including Alpine)
    # Format: name|size|mtime|type_desc
    # %n: name
    # %s: size
    # %Y: mtime (seconds)
    # %F: type (directory, regular file, etc)

    # We target directory contents
    target_pattern = f"'{path.rstrip('/')}'/*"

    # Using a shell loop to safely handle globbing and failures
    # We use a custom delimiter `|` to split fields
    stat_cmd = (
        f"for f in {target_pattern}; do stat -c '%n|%s|%Y|%F' \"$f\" 2>/dev/null; done"
    )

    exec_result = container.exec_run(["/bin/sh", "-c", stat_cmd])

    items = []

    if exec_result.exit_code == 0 and exec_result.output:
        output_str = exec_result.output.decode("utf-8").strip()
        if output_str:
            lines = output_str.split("\n")
            for line in lines:
                parts = line.split("|")
                if len(parts) >= 4:
                    full_path = parts[0]
                    size = int(parts[1])
                    mtime = int(parts[2])
                    type_str = parts[3].lower()

                    name = os.path.basename(full_path)

                    # Determine type
                    item_type = "file"
                    if "directory" in type_str:
                        item_type = "directory"
                    elif "link" in type_str:
                        # For symlinks, stat usually follows them or describes the link
                        # We might want to know if it's a link.
                        # stat -c %F returns "symbolic link"
                        pass

                    is_symlink = "symbolic link" in type_str

                    # Check if this item is a mount point
                    # For exec mode, items are mounted only if they are mount points themselves
                    # OR if we are somehow browsing inside a mount point that wasn't caught by the main logic (unlikely)
                    item_clean_path = full_path.rstrip("/")
                    is_mounted = item_clean_path in mount_destinations

                    items.append(
                        {
                            "name": name,
                            "type": "directory"
                            if is_dir and name == ""
                            else item_type,  # Handle root case? No, basename works.
                            "size": size,
                            "modified": mtime,
                            "is_symlink": is_symlink,
                            "is_mounted": is_mounted,
                        }
                    )
            return items

    # 2. Fallback to `ls -la` if stat failed or returned nothing (e.g. command not found)
    # This is much harder to parse reliably, but we do our best.
    # BusyBox ls -la:
    # drwxr-xr-x    1 root     root          4096 Dec 19 12:35 .

    ls_cmd = f"ls -la '{path}'"
    exec_result = container.exec_run(["/bin/sh", "-c", ls_cmd])

    if exec_result.exit_code != 0:
        raise HTTPException(
            status_code=404,
            detail=f"Path not found or not accessible inside container: {exec_result.output.decode('utf-8')}",
        )

    output_str = exec_result.output.decode("utf-8").strip()
    lines = output_str.split("\n")

    path_clean = path.rstrip("/")

    for line in lines:
        if line.startswith("total "):
            continue

        # Parse ls -l output
        # We assume standard fields: perms links owner group size date... name
        parts = re.split(r"\s+", line.strip())

        if len(parts) < 8:  # Minimal check
            continue

        perms = parts[0]

        # Determine basic type
        is_dir = perms.startswith("d")
        is_symlink = perms.startswith("l")
        item_type = "directory" if is_dir else "file"

        # Try to find size (usually index 4)
        try:
            size = int(parts[4])
        except (ValueError, IndexError):
            size = 0

        # Name is the hardest part.
        # Usually starts at index 8.
        # date is usually 3 parts (Mon Day Time/Year)
        # But let's assume index 8 is name start
        if len(parts) > 8:
            name_parts = parts[8:]
            name = " ".join(name_parts)

            # Filter . and ..
            if name == "." or name == "..":
                continue

            # Construct full path to check against mounts
            # Warning: `name` from ls -la might be "link -> target". We need to handle that.
            if " -> " in name:
                name = name.split(" -> ")[0]

            full_item_path = f"{path_clean}/{name}"
            is_mounted = full_item_path in mount_destinations

            items.append(
                {
                    "name": name,
                    "type": item_type,
                    "size": size,
                    "modified": 0,  # Hard to parse date reliably across distros
                    "is_symlink": is_symlink,
                    "is_mounted": is_mounted,
                }
            )

    return items


def create_file_tar(filename: str, content: str) -> bytes:
    """Create a tar archive containing a single file with content."""
    file_data = content.encode("utf-8")
    tar_stream = io.BytesIO()
    with tarfile.open(fileobj=tar_stream, mode="w") as tar:
        tarinfo = tarfile.TarInfo(name=filename)
        tarinfo.size = len(file_data)
        tarinfo.mtime = time.time()
        tar.addfile(tarinfo, io.BytesIO(file_data))
    return tar_stream.getvalue()


@router.put("/{container_id}/files")
async def update_container_file(container_id: str, request: FileUpdateRequest):
    """
    Update the content of a file inside a container.
    Supports both mounted files (direct host write) and non-mounted files (via docker put_archive).
    """
    if not request.path or not request.path.startswith("/"):
        raise HTTPException(
            status_code=400, detail="Path must be absolute (e.g., /data/config.json)"
        )

    client = get_docker_client()
    try:
        container = client.containers.get(container_id)
        mounts = container.attrs.get("Mounts", [])
        path = request.path

        # 1. Try to resolve to host path first (Same logic as get_container_files)
        path_clean = path.rstrip("/")
        best_match = None

        for mount in mounts:
            dest = mount.get("Destination")
            if not dest:
                continue

            dest_clean = dest.rstrip("/")

            if path_clean == dest_clean or path_clean.startswith(dest_clean + "/"):
                if best_match is None or len(dest_clean) > len(
                    best_match.get("Destination").rstrip("/")
                ):
                    best_match = mount

        # If mounted, write to host
        if best_match:
            mount_source = best_match.get("Source")
            mount_dest = best_match.get("Destination")

            mount_dest_clean = mount_dest.rstrip("/")
            path_clean = path.rstrip("/")

            if path_clean == mount_dest_clean:
                relative_path = ""
            else:
                relative_path = path_clean[len(mount_dest_clean) :].lstrip("/")

            host_abs_path = os.path.join(mount_source, relative_path)
            clean_host_abs_path = host_abs_path.lstrip("/")
            final_path = os.path.join(HOST_FILESYSTEM_ROOT, clean_host_abs_path)

            # Security checks
            if ".." in relative_path.split("/"):
                raise HTTPException(status_code=403, detail="Path traversal detected")

            # Ensure parent directory exists
            parent_dir = os.path.dirname(final_path)
            if not os.path.exists(parent_dir):
                raise HTTPException(
                    status_code=404,
                    detail=f"Parent directory not found on host: {parent_dir}",
                )

            # Write file
            try:
                with open(final_path, "w", encoding="utf-8") as f:
                    f.write(request.content)
                return {
                    "status": "success",
                    "message": f"File {path} updated successfully (via mount)",
                }
            except OSError as e:
                raise HTTPException(
                    status_code=500, detail=f"Error writing to host file: {str(e)}"
                )

        # 2. Not mounted, use docker put_archive
        # Verify parent directory exists inside container
        parent_dir_container = os.path.dirname(path)
        check_dir_cmd = f"test -d '{parent_dir_container}'"
        exit_code, _ = container.exec_run(["/bin/sh", "-c", check_dir_cmd])

        if exit_code != 0:
            raise HTTPException(
                status_code=404,
                detail=f"Parent directory does not exist inside container: {parent_dir_container}",
            )

        # Create tarball
        filename = os.path.basename(path)
        tar_data = create_file_tar(filename, request.content)

        # Upload
        try:
            container.put_archive(parent_dir_container, tar_data)
            return {
                "status": "success",
                "message": f"File {path} updated successfully (via docker exec)",
            }
        except Exception as e:
            raise HTTPException(
                status_code=500,
                detail=f"Error updating file inside container: {str(e)}",
            )

    except docker.errors.NotFound:
        raise HTTPException(status_code=404, detail="Container not found")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error updating file: {str(e)}")
    finally:
        client.close()


@router.get(
    "/{container_id}/files", response_model=Union[List[Dict[str, Any]], Dict[str, Any]]
)
async def get_container_files(container_id: str, path: str = ""):
    """
    Get list of files and directories in a container's mapped path.
    If path is a directory, returns a list of files.
    If path is a file, returns its content (text only, max 1MB).

    path: Absolute path inside the container (e.g., '/data').
    """
    if not path or not path.startswith("/"):
        raise HTTPException(
            status_code=400, detail="Path must be absolute (e.g., /data)"
        )

    client = get_docker_client()
    try:
        container = client.containers.get(container_id)
        mounts = container.attrs.get("Mounts", [])

        # Find the best matching mount (longest prefix)
        path_clean = path.rstrip("/")
        best_match = None

        for mount in mounts:
            dest = mount.get("Destination")
            if not dest:
                continue

            dest_clean = dest.rstrip("/")

            if path_clean == dest_clean or path_clean.startswith(dest_clean + "/"):
                if best_match is None or len(dest_clean) > len(
                    best_match.get("Destination").rstrip("/")
                ):
                    best_match = mount

        if not best_match:
            # Fallback to exec_run for non-mounted paths
            return await list_files_via_exec(container, path, mounts)

        # Calculate host path
        # Mount Source: /volume2/docker/gogs
        # Mount Dest: /data
        # Requested: /data/subdir
        # Relative: subdir
        # Host Target: /volume2/docker/gogs/subdir

        mount_source = best_match.get("Source")
        mount_dest = best_match.get("Destination")

        # Handle trailing slashes normalization
        mount_dest_clean = mount_dest.rstrip("/")
        path_clean = path.rstrip("/")

        if path_clean == mount_dest_clean:
            relative_path = ""
            host_abs_path = mount_source
        else:
            relative_path = path_clean[len(mount_dest_clean) :].lstrip("/")
            host_abs_path = os.path.join(mount_source, relative_path)

        # Map to our container's view of host fs
        # HOST_FILESYSTEM_ROOT = /hostfs
        # We need to strip leading / from host_abs_path carefully

        clean_host_abs_path = host_abs_path.lstrip("/")
        final_path = os.path.join(HOST_FILESYSTEM_ROOT, clean_host_abs_path)

        # Security checks
        # 1. Ensure we are actually inside the mount source (path traversal check)
        # But wait, host_abs_path is constructed by joining mount_source + relative_path.
        # Relative path comes from user input stripping the prefix.
        # We should verify relative_path doesn't contain ".."

        if ".." in relative_path.split("/"):
            raise HTTPException(status_code=403, detail="Path traversal detected")

        if not os.path.exists(final_path):
            raise HTTPException(
                status_code=404, detail=f"Path not found on host: {host_abs_path}"
            )

        # Check if it is a file and read content
        if os.path.isfile(final_path):
            # Limit size to 1MB
            try:
                size = os.path.getsize(final_path)
                if size > 1024 * 1024:
                    raise HTTPException(
                        status_code=400, detail="File too large to view (max 1MB)"
                    )

                with open(final_path, "r", encoding="utf-8") as f:
                    content = f.read()
                return {"content": content}
            except UnicodeDecodeError:
                raise HTTPException(status_code=400, detail="Binary file not supported")
            except OSError as e:
                raise HTTPException(
                    status_code=500, detail=f"Error reading file: {str(e)}"
                )

        if not os.path.isdir(final_path):
            raise HTTPException(status_code=400, detail="Path is not a directory")

        items = []
        with os.scandir(final_path) as it:
            for entry in it:
                try:
                    stat = entry.stat()
                    items.append(
                        {
                            "name": entry.name,
                            "type": "directory" if entry.is_dir() else "file",
                            "size": stat.st_size,
                            "modified": stat.st_mtime,
                            "is_symlink": entry.is_symlink(),
                            "is_mounted": True,
                        }
                    )
                except OSError:
                    continue

        return items

    except docker.errors.NotFound:
        raise HTTPException(status_code=404, detail="Container not found")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error listing files: {str(e)}")
    finally:
        client.close()


@router.get("/{container_id}", response_model=Dict[str, Any])
async def get_container_details(container_id: str):
    """
    Get detailed information about a specific container.
    """
    client = get_docker_client()
    try:
        container = client.containers.get(container_id)
        return container.attrs
    except docker.errors.NotFound:
        raise HTTPException(status_code=404, detail="Container not found")
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Error retrieving container details: {str(e)}"
        )
    finally:
        client.close()


@router.post("/{container_id}/restart")
async def restart_container(container_id: str):
    """
    Restart a specific Docker container by its ID or Name.
    """
    client = get_docker_client()
    try:
        container = client.containers.get(container_id)
        container.restart()
        return {
            "status": "success",
            "message": f"Container {container.name} ({container.id[:12]}) restarted successfully",
        }
    except docker.errors.NotFound:
        raise HTTPException(
            status_code=404, detail=f"Container {container_id} not found"
        )
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Error restarting container: {str(e)}"
        )
    finally:
        client.close()


@router.post("/{container_id}/start")
async def start_container(container_id: str):
    """
    Start a specific Docker container by its ID or Name.
    """
    client = get_docker_client()
    try:
        container = client.containers.get(container_id)
        container.start()
        return {
            "status": "success",
            "message": f"Container {container.name} ({container.id[:12]}) started successfully",
        }
    except docker.errors.NotFound:
        raise HTTPException(
            status_code=404, detail=f"Container {container_id} not found"
        )
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Error starting container: {str(e)}"
        )
    finally:
        client.close()


@router.post("/{container_id}/stop")
async def stop_container(container_id: str):
    """
    Stop a specific Docker container by its ID or Name.
    """
    client = get_docker_client()
    try:
        container = client.containers.get(container_id)
        container.stop()
        return {
            "status": "success",
            "message": f"Container {container.name} ({container.id[:12]}) stopped successfully",
        }
    except docker.errors.NotFound:
        raise HTTPException(
            status_code=404, detail=f"Container {container_id} not found"
        )
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Error stopping container: {str(e)}"
        )
    finally:
        client.close()


@router.post("/{container_id}/kill")
async def kill_container(container_id: str):
    """
    Force stop (kill) a specific Docker container by its ID or Name.
    """
    client = get_docker_client()
    try:
        container = client.containers.get(container_id)
        container.kill()
        return {
            "status": "success",
            "message": f"Container {container.name} ({container.id[:12]}) killed successfully",
        }
    except docker.errors.NotFound:
        raise HTTPException(
            status_code=404, detail=f"Container {container_id} not found"
        )
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Error killing container: {str(e)}"
        )
    finally:
        client.close()


@router.post("/{container_id}/pause")
async def pause_container(container_id: str):
    """
    Pause a specific Docker container by its ID or Name.
    """
    client = get_docker_client()
    try:
        container = client.containers.get(container_id)
        container.pause()
        return {
            "status": "success",
            "message": f"Container {container.name} ({container.id[:12]}) paused successfully",
        }
    except docker.errors.NotFound:
        raise HTTPException(
            status_code=404, detail=f"Container {container_id} not found"
        )
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Error pausing container: {str(e)}"
        )
    finally:
        client.close()


@router.post("/{container_id}/unpause")
async def unpause_container(container_id: str):
    """
    Unpause (resume) a specific Docker container by its ID or Name.
    """
    client = get_docker_client()
    try:
        container = client.containers.get(container_id)
        container.unpause()
        return {
            "status": "success",
            "message": f"Container {container.name} ({container.id[:12]}) unpaused successfully",
        }
    except docker.errors.NotFound:
        raise HTTPException(
            status_code=404, detail=f"Container {container_id} not found"
        )
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Error unpausing container: {str(e)}"
        )
    finally:
        client.close()


@router.delete("/{container_id}")
async def delete_container(container_id: str, force: bool = True, v: bool = False):
    """
    Remove a specific Docker container by its ID or Name.
    Query parameters:
    - force: Force the removal of a running container (main process will be killed).
    - v: Remove the volumes associated with the container.
    """
    client = get_docker_client()
    try:
        container = client.containers.get(container_id)
        container.remove(force=force, v=v)
        return {
            "status": "success",
            "message": f"Container {container.name} ({container.id[:12]}) removed successfully",
        }
    except docker.errors.NotFound:
        raise HTTPException(
            status_code=404, detail=f"Container {container_id} not found"
        )
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Error removing container: {str(e)}"
        )
    finally:
        client.close()
