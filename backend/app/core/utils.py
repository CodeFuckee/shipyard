import docker
from fastapi import HTTPException
import socket
import shlex
import argparse
from typing import Dict, Any


def get_docker_client():
    try:
        return docker.from_env()
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Failed to connect to Docker daemon: {str(e)}"
        )


def get_self_container(client):
    """
    Get the container object for the current running process.
    Returns None if not found or not running in a container.
    """
    self_id = get_current_container_id()
    if not self_id:
        return None

    try:
        return client.containers.get(self_id)
    except docker.errors.NotFound:
        # Try finding by prefix if self_id is short ID
        if len(self_id) < 64:
            # List all and check prefix
            containers = client.containers.list(all=True)
            for c in containers:
                if c.id.startswith(self_id):
                    return c
    except Exception:
        pass

    return None


def get_current_container_id():
    """
    Try to resolve the current container's ID.
    Returns hostname (usually short ID) or full ID from cgroup.
    """
    try:
        # Try to read cgroup to find full container ID
        with open("/proc/self/cgroup", "r") as f:
            for line in f:
                if "docker" in line:
                    path = line.split(":")[-1].strip()
                    container_id = path.split("/")[-1]
                    if container_id:
                        return container_id
    except Exception:
        pass
    # Fallback to hostname
    return socket.gethostname()


def process_container_summary(container, self_id: str = None) -> Dict[str, Any]:
    # Stack
    labels = container.labels or {}
    stack = labels.get("com.docker.compose.project", "")

    # Image
    image = container.attrs.get("Image", "")
    if image.startswith("sha256:"):
        try:
            if container.image and container.image.tags:
                image = container.image.tags[0]
        except Exception:
            pass

    # Ports
    ports_str_list = []
    ports_list = []
    raw_ports = container.attrs.get("Ports", [])
    for p in raw_ports:
        if "PublicPort" in p:
            ports_str_list.append(f"{p['PublicPort']}->{p['PrivatePort']}/{p['Type']}")
        ports_list.append(
            {
                "public_port": p.get("PublicPort"),
                "private_port": p.get("PrivatePort"),
                "type": p.get("Type"),
            }
        )
    ports = ", ".join(ports_str_list)

    is_self = False
    if self_id:
        # Check against full ID or short ID
        if container.id == self_id:
            is_self = True
        elif container.id.startswith(self_id):  # self_id is short
            is_self = True
        elif self_id.startswith(
            container.id
        ):  # self_id is somehow longer (unlikely if container.id is full)
            is_self = True

    return {
        "id": container.id,
        "name": container.name,
        "status": str(container.status).lower(),
        "stack": stack,
        "image": image,
        "ports": ports,
        "ports_list": ports_list,
        "is_self": is_self,
    }


class NoExitArgumentParser(argparse.ArgumentParser):
    """ArgumentParser 子类，解析失败时抛出 ValueError 而非调用 sys.exit。"""

    def error(self, message):
        raise ValueError(message)


def parse_docker_run_command(cmd: str) -> Dict[str, Any]:
    """
    将 docker run 命令字符串解析为 docker-py 参数。

    示例:
        "docker run -d -p 8080:80 --name my-nginx nginx"
    """
    parser = NoExitArgumentParser(add_help=False)

    # 位置参数
    parser.add_argument("image", nargs="?")
    parser.add_argument("command", nargs=argparse.REMAINDER)

    # 常用参数
    parser.add_argument("-d", "--detach", action="store_true")
    parser.add_argument("--name")
    parser.add_argument("-p", "--publish", action="append", default=[])
    parser.add_argument("-v", "--volume", action="append", default=[])
    parser.add_argument("-e", "--env", action="append", default=[])
    parser.add_argument("--restart")
    parser.add_argument("--network")
    parser.add_argument("-i", "--interactive", action="store_true")
    parser.add_argument("-t", "--tty", action="store_true")
    parser.add_argument("--rm", action="store_true")
    parser.add_argument("--privileged", action="store_true")

    # 预处理：移除 'docker run' 前缀
    parts = shlex.split(cmd)
    if not parts:
        raise ValueError("空命令")

    start_idx = 0
    if parts[0] == "docker":
        if len(parts) > 1 and parts[1] == "run":
            start_idx = 2
    elif parts[0] == "run":
        start_idx = 1

    args_parts = parts[start_idx:]
    if not args_parts:
        raise ValueError("未提供参数")

    try:
        args = parser.parse_args(args_parts)
    except ValueError as e:
        raise ValueError(f"解析命令失败: {str(e)}")

    if not args.image:
        raise ValueError("镜像名称为必填项")

    # 构造 docker-py 参数
    params = {
        "image": args.image,
        "command": args.command,
        "detach": args.detach,
        "name": args.name,
        "ports": {},
        "volumes": [],
        "environment": {},
        "network": args.network,
        "stdin_open": args.interactive,
        "tty": args.tty,
        "auto_remove": args.rm,
        "privileged": args.privileged,
    }

    if args.restart:
        params["restart_policy"] = {"Name": args.restart}

    # 处理端口: -p 8080:80 或 -p 80
    for p in args.publish:
        if ":" in p:
            parts = p.split(":")
            if len(parts) == 2:
                host_port, container_port = parts
                params["ports"][f"{container_port}/tcp"] = int(host_port)
            elif len(parts) == 3:
                # ip:host_port:container_port
                ip, host_port, container_port = parts
                params["ports"][f"{container_port}/tcp"] = (ip, int(host_port))
        else:
            # 容器端口（随机主机端口）
            params["ports"][f"{p}/tcp"] = None

    # 处理卷: -v /host:/container
    params["volumes"] = args.volume

    # 处理环境变量: -e KEY=VAL
    for e in args.env:
        if "=" in e:
            k, v = e.split("=", 1)
            params["environment"][k] = v
        else:
            # -e KEY（从宿主机透传？这里不支持，跳过或警告）
            pass

    return params
