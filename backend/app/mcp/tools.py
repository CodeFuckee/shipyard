"""
MCP 工具定义 — Docker 资源管理工具集。

通过 register_all_tools(server) 将 33 个 Docker 管理工具注册到 MCP Server。
这些工具被 AI 助手（如 Claude）通过 MCP 协议调用，实现对 Docker 资源的声明式管理。

=== 工具分组 ===

本模块定义了 6 组共 33 个工具：

【容器工具 — 11 个】
  list_containers     — 列出所有容器（支持摘要模式）
  get_container       — 获取指定容器的完整详情
  get_container_logs  — 获取容器日志
  start_container     — 启动已停止的容器
  stop_container      — 正常停止运行中的容器
  restart_container   — 重启容器
  kill_container      — 强制终止容器（SIGKILL）
  pause_container     — 暂停容器中的所有进程
  unpause_container   — 恢复暂停的容器
  remove_container    — 删除容器（可选强制+删除卷）
  run_container       — 使用 docker run 命令字符串创建新容器

【镜像工具 — 4 个】
  list_images    — 列出所有镜像（含使用状态）
  get_image      — 获取指定镜像详情
  pull_image     — 从注册表拉取镜像
  remove_image   — 删除镜像

【网络工具 — 2 个】
  list_networks  — 列出所有 Docker 网络
  get_network    — 获取指定网络详情

【卷工具 — 3 个】
  list_volumes   — 列出所有卷（含使用状态）
  get_volume     — 获取指定卷详情（含使用它的容器列表）
  remove_volume  — 删除卷

【系统工具 — 4 个】
  get_system_info       — 聚合系统信息（Docker 统计 + Git 版本 + 系统资源）
  get_system_usage      — 实时系统资源使用（CPU、内存、磁盘、GPU）
  list_stacks           — 列出 Docker Compose 项目
  get_stack_containers  — 获取指定 Compose 项目的所有容器

【项目工具 — 9 个】
  list_projects       — 列出所有项目
  get_project         — 获取项目详情
  create_project      — 创建项目（自动生成 Dockerfile + docker-compose.yaml）
  delete_project      — 删除项目（清理文件 + compose down）
  get_project_file    — 读取项目 Dockerfile 或 docker-compose.yaml
  update_project_file — 更新项目 Dockerfile 或 docker-compose.yaml
  build_project       — 触发 Docker 镜像构建（同步模式，返回构建日志）
  project_up          — 启动项目容器（docker compose up）
  project_down        — 停止项目容器（docker compose down）

=== 工具函数设计规范 ===

每个工具函数遵循统一的设计模式：

1. 参数校验：通过函数签名中的类型注解进行
2. 客户端获取：调用 get_docker_client_safe() 获取 Docker 连接
3. 核心逻辑：执行 Docker 操作
4. 错误处理：捕获 docker.errors 异常，转为 RuntimeError（含中文描述）
5. 资源释放：finally 块中调用 client.close()

=== 与其他模块的关系 ===

- helpers.py：提供 get_docker_client_safe()、get_db_session()、check_api_key()
- app.core.utils：提供 process_container_summary()、parse_docker_run_command()
- auth_provider.py：提供 OAuth 认证（独立于工具层，由 MCP 框架处理）
"""

import os
import pathlib
import shutil
import subprocess
import uuid
from datetime import datetime

import docker
import git
import psutil
from mcp.server import MCPServer

from app.core.config import PROJECTS_DIR
from app.core.utils import (
    get_current_container_id,
    parse_docker_run_command,
    process_container_summary,
)
from app.db.models import ProjectModel

from .helpers import get_docker_client_safe, get_db_session

# ---- 可选依赖 ----
# GPUtil 用于 GPU 监控，不是所有环境都需要
# 如果未安装，GPU 相关功能静默跳过
try:
    import GPUtil
except ImportError:
    GPUtil = None


def register_all_tools(server: MCPServer) -> None:
    """向 MCP Server 注册所有 Docker 管理工具。

    本函数使用 @server.tool() 装饰器注册 24 个工具函数。
    每个工具通过 description 参数提供中文描述，
    AI 助手根据描述来决定何时调用哪个工具。

    Args:
        server: MCPServer 实例，工具会被注册到此实例上

    工具函数的类型注解（参数类型和返回类型）会被 MCPServer 自动
    转换为 MCP 工具的 JSON Schema，供客户端进行参数验证。

    参数:
        server: MCPServer 实例，工具会被注册到此实例上
    """

    # ================================================================
    # 容器工具（Container Tools）
    # 提供容器的完整生命周期管理：列出、查看、启动、停止、重启、终止、
    # 暂停、恢复、删除、创建。
    # ================================================================

    @server.tool(description="列出所有 Docker 容器。可选择返回摘要信息或完整属性。")
    def list_containers(summary: bool = False, all: bool = True) -> list[dict]:
        """列出所有 Docker 容器。

        参数:
            summary: True=返回精简摘要（名称、状态、端口、网络等），
                     False=返回完整 attrs 字典
            all: True=包括已停止的容器，False=仅运行中的容器

        返回:
            容器信息字典列表，摘要模式下包含：
            - id, name, image, status, ports, networks, created, labels

        设计说明:
            摘要模式（summary=True）通过 process_container_summary() 处理，
            输出的数据量与 docker ps 命令类似，适合 AI 助手快速了解环境概况。
            self_id 用于标记当前运行的容器（避免 AI 误操作自身）。
        """
        client = get_docker_client_safe()
        try:
            containers = client.containers.list(all=all)
            if summary:
                self_id = get_current_container_id()
                return [process_container_summary(c, self_id) for c in containers]
            return [
                {
                    "id": c.id,
                    "short_id": c.short_id,
                    "name": c.name,
                    "status": str(c.status).lower(),  # 统一小写，如 "running", "exited"
                    "image": str(c.image),
                    "attrs": c.attrs,  # 完整的 Docker inspect 输出
                }
                for c in containers
            ]
        finally:
            client.close()

    @server.tool(description="通过 ID 或名称获取指定容器的详细信息。")
    def get_container(container_id: str) -> dict:
        """获取单个容器的完整详情。

        等同于 docker inspect <container> 命令的输出。

        参数:
            container_id: 容器 ID（完整或短 ID）或名称

        返回:
            容器的完整 attrs 字典，包含所有配置、网络、挂载等信息

        异常:
            RuntimeError: 容器不存在时抛出
        """
        client = get_docker_client_safe()
        try:
            return client.containers.get(container_id).attrs
        except docker.errors.NotFound:
            raise RuntimeError(f"未找到容器：{container_id}")
        finally:
            client.close()

    @server.tool(description="获取指定容器的日志。")
    def get_container_logs(
        container_id: str, tail: int = 2000, timestamps: bool = True
    ) -> dict:
        """获取容器的 stdout/stderr 日志。

        参数:
            container_id: 容器 ID 或名称
            tail: 返回日志的最后 N 行（从尾部开始）。默认 2000 行，
                  设为 "all" 可获取全部日志
            timestamps: 是否在每行日志前添加时间戳（RFC3339Nano 格式）

        返回:
            {"logs": "日志内容字符串"}

        编码处理:
            使用 UTF-8 解码，遇到无法解码的字节用 replacement character (�) 替换。
            这处理了容器输出二进制数据或非 UTF-8 编码的情况。
        """
        client = get_docker_client_safe()
        try:
            container = client.containers.get(container_id)
            logs = container.logs(tail=tail, timestamps=timestamps).decode(
                "utf-8", errors="replace"
            )
            return {"logs": logs}
        except docker.errors.NotFound:
            raise RuntimeError(f"未找到容器：{container_id}")
        finally:
            client.close()

    @server.tool(description="启动一个已停止的容器。")
    def start_container(container_id: str) -> dict:
        """启动一个已停止的容器。

        相当于 docker start <container>。

        参数:
            container_id: 容器 ID 或名称

        返回:
            {"status": "success", "message": "容器 xxx 已启动"}
        """
        client = get_docker_client_safe()
        try:
            container = client.containers.get(container_id)
            container.start()
            return {
                "status": "success",
                "message": f"容器 {container.name} 已启动",
            }
        except docker.errors.NotFound:
            raise RuntimeError(f"未找到容器：{container_id}")
        finally:
            client.close()

    @server.tool(description="正常停止一个正在运行的容器。")
    def stop_container(container_id: str) -> dict:
        """正常停止一个正在运行的容器。

        发送 SIGTERM 信号，等待容器优雅退出。
        默认超时 10 秒后发送 SIGKILL 强制终止。

        相当于 docker stop <container>。

        参数:
            container_id: 容器 ID 或名称

        返回:
            {"status": "success", "message": "容器 xxx 已停止"}
        """
        client = get_docker_client_safe()
        try:
            container = client.containers.get(container_id)
            container.stop()
            return {
                "status": "success",
                "message": f"容器 {container.name} 已停止",
            }
        except docker.errors.NotFound:
            raise RuntimeError(f"未找到容器：{container_id}")
        finally:
            client.close()

    @server.tool(description="重启一个容器。")
    def restart_container(container_id: str) -> dict:
        """重启一个容器。

        相当于 docker restart <container>。
        先停止再启动，容器内的临时文件系统会被保留
        （除非使用了 --rm 选项且容器被删除）。

        参数:
            container_id: 容器 ID 或名称

        返回:
            {"status": "success", "message": "容器 xxx 已重启"}
        """
        client = get_docker_client_safe()
        try:
            container = client.containers.get(container_id)
            container.restart()
            return {
                "status": "success",
                "message": f"容器 {container.name} 已重启",
            }
        except docker.errors.NotFound:
            raise RuntimeError(f"未找到容器：{container_id}")
        finally:
            client.close()

    @server.tool(description="强制终止（kill）一个容器。")
    def kill_container(container_id: str) -> dict:
        """强制终止一个容器。

        直接发送 SIGKILL 信号，不给容器优雅退出的机会。
        相当于 docker kill <container>。

        与 stop_container 的区别：
        - stop: SIGTERM → 等待超时 → SIGKILL（优雅退出）
        - kill: 直接 SIGKILL（立即终止）

        参数:
            container_id: 容器 ID 或名称

        返回:
            {"status": "success", "message": "容器 xxx 已终止"}
        """
        client = get_docker_client_safe()
        try:
            container = client.containers.get(container_id)
            container.kill()
            return {
                "status": "success",
                "message": f"容器 {container.name} 已终止",
            }
        except docker.errors.NotFound:
            raise RuntimeError(f"未找到容器：{container_id}")
        finally:
            client.close()

    @server.tool(description="暂停容器中的所有进程。")
    def pause_container(container_id: str) -> dict:
        """暂停容器中的所有进程。

        使用 cgroups freezer 功能冻结容器进程。
        相当于 docker pause <container>。
        恢复使用 unpause_container。

        参数:
            container_id: 容器 ID 或名称

        返回:
            {"status": "success", "message": "容器 xxx 已暂停"}
        """
        client = get_docker_client_safe()
        try:
            container = client.containers.get(container_id)
            container.pause()
            return {
                "status": "success",
                "message": f"容器 {container.name} 已暂停",
            }
        except docker.errors.NotFound:
            raise RuntimeError(f"未找到容器：{container_id}")
        finally:
            client.close()

    @server.tool(description="恢复（取消暂停）一个容器。")
    def unpause_container(container_id: str) -> dict:
        """恢复一个暂停的容器。

        取消 cgroups freezer 的冻结状态，容器进程恢复运行。
        相当于 docker unpause <container>。

        参数:
            container_id: 容器 ID 或名称

        返回:
            {"status": "success", "message": "容器 xxx 已恢复"}
        """
        client = get_docker_client_safe()
        try:
            container = client.containers.get(container_id)
            container.unpause()
            return {
                "status": "success",
                "message": f"容器 {container.name} 已恢复",
            }
        except docker.errors.NotFound:
            raise RuntimeError(f"未找到容器：{container_id}")
        finally:
            client.close()

    @server.tool(description="删除一个容器。可选择强制删除和同时删除关联的卷。")
    def remove_container(
        container_id: str, force: bool = True, v: bool = False
    ) -> dict:
        """删除一个容器。

        相当于 docker rm <container>。

        参数:
            container_id: 容器 ID 或名称
            force: True=强制删除运行中的容器（先 SIGKILL 再删除），默认为 True
            v: True=同时删除容器关联的匿名卷，默认为 False

        返回:
            {"status": "success", "message": "容器 xxx 已删除"}

        安全注意事项:
            - v=True 会删除匿名卷中的数据，不可恢复
            - 命名卷（通过 docker volume create 创建）不会被删除
        """
        client = get_docker_client_safe()
        try:
            container = client.containers.get(container_id)
            container.remove(force=force, v=v)
            return {
                "status": "success",
                "message": f"容器 {container_id} 已删除",
            }
        except docker.errors.NotFound:
            raise RuntimeError(f"未找到容器：{container_id}")
        finally:
            client.close()

    @server.tool(
        description=(
            "使用 docker run 命令字符串运行一个新容器。"
            "例如: 'docker run -d -p 8080:80 --name my-nginx nginx'。"
            "注意：始终以分离模式运行，避免阻塞。"
        )
    )
    def run_container(command: str) -> dict:
        """使用 docker run 命令字符串创建并启动新容器。

        这是唯一接受自然命令字符串的工具——AI 助手可以直接
        写出类似命令行的 docker run 指令。

        参数:
            command: docker run 命令字符串（可带或不带 "docker run" 前缀）
                     例如："docker run -d -p 8080:80 --name my-nginx nginx:latest"

        返回:
            {"status": "success", "id": "完整ID", "short_id": "短ID", "name": "容器名"}

        命令解析:
            使用 parse_docker_run_command() 将命令字符串解析为 docker-py 的
            **kwargs 参数，支持镜像名、端口映射、环境变量、卷挂载、
            重启策略等常用选项。

        安全机制:
            强制 detach=True（分离模式），避免 MCP 调用阻塞等待容器退出。
            即使命令中指定了 -it 或未指定 -d，也会自动添加。

        异常:
            RuntimeError("无效命令"): 命令字符串无法解析
            RuntimeError("未找到镜像"): 指定的镜像不存在
            RuntimeError("Docker API 错误"): 其他 Docker 引擎错误
        """
        client = get_docker_client_safe()
        try:
            # 将 docker run 命令字符串解析为 docker-py 的 run() 参数
            params = parse_docker_run_command(command)

            # 强制分离模式：避免 MCP 调用阻塞，等待容器退出
            if not params.get("detach"):
                params["detach"] = True

            container = client.containers.run(**params)
            return {
                "status": "success",
                "id": container.id,
                "short_id": container.short_id,
                "name": container.name,
            }
        except ValueError as e:
            raise RuntimeError(f"无效命令：{e}")
        except docker.errors.ImageNotFound as e:
            raise RuntimeError(f"未找到镜像：{e}")
        except docker.errors.APIError as e:
            raise RuntimeError(f"Docker API 错误：{e}")
        finally:
            client.close()

    # ================================================================
    # 镜像工具（Image Tools）
    # 提供镜像的管理：列出、查看、拉取、删除。
    # ================================================================

    @server.tool(description="列出所有 Docker 镜像，含使用状态。")
    def list_images() -> list[dict]:
        """列出所有 Docker 镜像及其使用状态。

        返回每个镜像的基本信息，同时标记哪些镜像正在被容器使用。
        "in_use" 字段可以帮助 AI 助手判断哪些镜像可以安全删除。

        返回:
            镜像信息字典列表，每个包含：
            - id: 完整镜像 ID
            - tags: 标签列表（如 ["nginx:latest", "nginx:1.25"]）
            - created: 创建时间（ISO 格式）
            - size: 镜像大小（字节）
            - labels: 镜像标签（metadata）
            - short_id: 短 ID（前 12 字符）
            - in_use: 是否至少有一个容器使用此镜像

        性能考虑:
            需要同时查询容器列表来确定 in_use 状态，
            对大型环境（>100 容器）可能较慢。
        """
        client = get_docker_client_safe()
        try:
            images = client.images.list()
            # 收集所有容器使用的镜像 ID，用于计算 in_use 字段
            containers = client.containers.list(all=True)
            used_image_ids = {c.attrs["Image"] for c in containers}
            return [
                {
                    "id": img.id,
                    "tags": img.tags,
                    "created": img.attrs.get("Created"),
                    "size": img.attrs.get("Size"),
                    "labels": img.labels,
                    "short_id": img.short_id,
                    "in_use": img.id in used_image_ids,
                }
                for img in images
            ]
        finally:
            client.close()

    @server.tool(description="通过 ID 或名称（标签）获取指定镜像的详细信息。")
    def get_image(image_id: str) -> dict:
        """获取指定镜像的完整详情（含使用状态）。

        参数:
            image_id: 镜像 ID（完整或短 ID）或名称/标签（如 "nginx:latest"）

        返回:
            镜像完整信息字典，在标准 attrs 基础上增加了：
            - id, short_id, tags: 从 Image 对象提取
            - in_use: 是否被容器使用

        异常:
            RuntimeError: 镜像不存在时抛出
        """
        client = get_docker_client_safe()
        try:
            image = client.images.get(image_id)
            containers = client.containers.list(all=True)
            used_image_ids = {c.attrs["Image"] for c in containers}
            data = dict(image.attrs or {})
            data["id"] = image.id
            data["short_id"] = image.short_id
            data["tags"] = image.tags
            data["in_use"] = image.id in used_image_ids
            return data
        except docker.errors.NotFound:
            raise RuntimeError(f"未找到镜像：{image_id}")
        finally:
            client.close()

    @server.tool(description="从注册表拉取一个 Docker 镜像。")
    def pull_image(image: str, tag: str = "latest") -> dict:
        """从 Docker 注册表拉取镜像。

        相当于 docker pull <image>:<tag>。
        支持 Docker Hub 和私有注册表。

        参数:
            image: 镜像名称，如 "nginx"、"python"、"myregistry.example.com/myapp"
            tag: 镜像标签，默认为 "latest"

        返回:
            {"status": "success", "id": "镜像ID", "tags": [...], "message": "..."}

        异常:
            RuntimeError: 拉取失败时抛出（如网络问题、认证失败、镜像不存在）

        注意:
            拉取大型镜像可能需要较长时间，MCP 客户端应考虑设置超时。
        """
        client = get_docker_client_safe()
        try:
            pulled = client.images.pull(image, tag=tag)
            return {
                "status": "success",
                "id": pulled.id,
                "tags": pulled.tags,
                "message": f"镜像 {image}:{tag} 已拉取",
            }
        except docker.errors.APIError as e:
            raise RuntimeError(f"Docker API 错误：{e}")
        finally:
            client.close()

    @server.tool(
        description=("删除一个 Docker 镜像。image_id 可以是短 ID、完整 ID 或名称。")
    )
    def remove_image(image_id: str, force: bool = False) -> dict:
        """删除一个 Docker 镜像。

        相当于 docker rmi <image>。

        参数:
            image_id: 镜像 ID（完整或短 ID）或名称/标签
            force: True=强制删除（即使有容器在使用），默认为 False

        返回:
            {"status": "success", "message": "镜像 xxx 已删除"}

        异常:
            RuntimeError("未找到镜像"): 镜像不存在
            RuntimeError("删除镜像失败"): 镜像正在使用或其它错误

        安全注意事项:
            - force=True 会删除正在使用的镜像，可能导致容器无法重启
            - 建议先通过 list_images() 确认镜像的 in_use 状态
        """
        client = get_docker_client_safe()
        try:
            client.images.remove(image=image_id, force=force)
            return {
                "status": "success",
                "message": f"镜像 {image_id} 已删除",
            }
        except docker.errors.ImageNotFound:
            raise RuntimeError(f"未找到镜像：{image_id}")
        except docker.errors.APIError as e:
            raise RuntimeError(f"删除镜像失败：{e}")
        finally:
            client.close()

    # ================================================================
    # 网络工具（Network Tools）
    # 提供 Docker 网络的查看功能。
    # ================================================================

    @server.tool(description="列出所有 Docker 网络。")
    def list_networks() -> list[dict]:
        """列出所有 Docker 网络。

        相当于 docker network ls + docker network inspect。

        返回:
            网络信息字典列表，每个包含：
            - id: 完整网络 ID
            - name: 网络名称（如 "bridge", "host", "my-network"）
            - driver: 网络驱动（如 "bridge", "overlay", "macvlan"）
            - scope: 作用域（"local" / "swarm" / "global"）
            - ipam: IP 地址管理配置（子网、网关、IP 范围）
            - containers: 连接到该网络的容器列表（含 IPv4/IPv6 地址）
            - short_id: 短 ID
            - created: 创建时间
        """
        client = get_docker_client_safe()
        try:
            networks = client.networks.list()
            return [
                {
                    "id": net.id,
                    "name": net.name,
                    "driver": net.attrs.get("Driver"),
                    "scope": net.attrs.get("Scope"),
                    "ipam": net.attrs.get("IPAM"),
                    "containers": net.attrs.get("Containers"),
                    "short_id": net.short_id,
                    "created": net.attrs.get("Created"),
                }
                for net in networks
            ]
        finally:
            client.close()

    @server.tool(description="通过 ID 或名称获取指定网络的详细信息。")
    def get_network(network_id: str) -> dict:
        """获取指定网络的完整详情。

        相当于 docker network inspect <network>。

        参数:
            network_id: 网络 ID 或名称

        返回:
            网络的完整 attrs 字典

        异常:
            RuntimeError: 网络不存在时抛出
        """
        client = get_docker_client_safe()
        try:
            return client.networks.get(network_id).attrs
        except docker.errors.NotFound:
            raise RuntimeError(f"未找到网络：{network_id}")
        finally:
            client.close()

    # ================================================================
    # 卷工具（Volume Tools）
    # 提供 Docker 卷的管理：列出、查看、删除。
    # ================================================================

    @server.tool(description="列出所有 Docker 卷，含使用状态。")
    def list_volumes() -> list[dict]:
        """列出所有 Docker 卷及其使用状态。

        返回每个卷的基本信息，同时标记哪些卷正在被容器使用。
        "in_use" 字段帮助 AI 助手判断哪些卷可以安全删除。

        使用状态检测：
            通过检查所有容器的 Mounts 配置，收集被 volume 类型挂载使用的卷名。

        返回:
            卷信息字典列表，每个包含：
            - id: 卷 ID
            - name: 卷名称
            - driver: 卷驱动（通常为 "local"）
            - created: 创建时间
            - mountpoint: 宿主机上的挂载路径
            - labels: 卷标签
            - in_use: 是否至少有一个容器挂载此卷
        """
        client = get_docker_client_safe()
        try:
            volumes = client.volumes.list()
            # 收集所有容器使用的卷名，用于计算 in_use 字段
            containers = client.containers.list(all=True)
            used_volume_names: set[str] = set()
            for c in containers:
                for m in c.attrs.get("Mounts", []):
                    if m.get("Type") == "volume":
                        name = m.get("Name")
                        if name:
                            used_volume_names.add(name)
            return [
                {
                    "id": vol.id,
                    "name": vol.name,
                    "driver": vol.attrs.get("Driver"),
                    "created": vol.attrs.get("CreatedAt"),
                    "mountpoint": vol.attrs.get("Mountpoint"),
                    "labels": vol.attrs.get("Labels"),
                    "in_use": vol.name in used_volume_names,
                }
                for vol in volumes
            ]
        finally:
            client.close()

    @server.tool(description="通过 ID 或名称获取指定卷的详细信息。")
    def get_volume(volume_id: str) -> dict:
        """获取指定卷的完整详情，包含使用它的容器列表。

        参数:
            volume_id: 卷 ID 或名称

        返回:
            卷完整信息字典，在标准 attrs 基础上增加了：
            - in_use: 是否被使用
            - used_by_containers: 使用此卷的容器名称列表

        异常:
            RuntimeError: 卷不存在时抛出
        """
        client = get_docker_client_safe()
        try:
            volume = client.volumes.get(volume_id)
            # 查找所有使用此卷的容器
            containers = client.containers.list(all=True)
            used_by: list[str] = []
            for c in containers:
                for m in c.attrs.get("Mounts", []):
                    if m.get("Type") == "volume" and m.get("Name") == volume.name:
                        used_by.append(c.name)
                        break  # 每个容器只添加一次

            data = dict(volume.attrs)
            data["in_use"] = len(used_by) > 0
            data["used_by_containers"] = used_by
            return data
        except docker.errors.NotFound:
            raise RuntimeError(f"未找到卷：{volume_id}")
        finally:
            client.close()

    @server.tool(description="删除一个 Docker 卷。")
    def remove_volume(volume_id: str, force: bool = False) -> dict:
        """删除一个 Docker 卷。

        相当于 docker volume rm <volume>。

        参数:
            volume_id: 卷 ID 或名称
            force: True=强制删除（即使卷正在使用），默认为 False

        返回:
            {"status": "success", "message": "卷 xxx 已删除"}

        异常:
            RuntimeError("未找到卷"): 卷不存在
            RuntimeError("卷正在使用中"): 卷被容器挂载且未使用 force=True
            RuntimeError("Docker API 错误"): 其他引擎错误

        安全注意事项:
            - 删除卷会永久删除其中的数据，不可恢复
            - 建议先通过 get_volume() 确认 used_by_containers 列表
        """
        client = get_docker_client_safe()
        try:
            volume = client.volumes.get(volume_id)
            volume.remove(force=force)
            return {
                "status": "success",
                "message": f"卷 {volume_id} 已删除",
            }
        except docker.errors.NotFound:
            raise RuntimeError(f"未找到卷：{volume_id}")
        except docker.errors.APIError as e:
            # 区分"卷正在使用"和其他 API 错误
            if "in use" in str(e).lower():
                raise RuntimeError(f"卷正在使用中：{e}")
            raise RuntimeError(f"Docker API 错误：{e}")
        finally:
            client.close()

    # ================================================================
    # 系统工具（System Tools）
    # 提供系统级别的信息查询：Docker 统计、Git 版本、系统资源、Compose 项目。
    # ================================================================

    @server.tool(description="获取聚合系统信息，包括 Docker 统计、Git 版本和系统资源。")
    def get_system_info() -> dict:
        """获取聚合系统信息。

        一次性返回三类信息，方便 AI 助手快速了解环境全貌：
        1. Docker 统计（容器数量、镜像数量、运行状态）
        2. Git 版本（分支、commit、作者、日期）
        3. 系统资源（CPU、内存使用情况）

        返回:
            {
                "docker": {"containers": {"total": N, "running": N, "stopped": N}, "images": N},
                "git": {"branch": "...", "commit_hash": "...", ...},
                "system": {"cpu": {...}, "memory": {...}}
            }

        容错设计:
            每类信息独立采集。如果某类信息获取失败（如不在 git 仓库中），
            对应的键值会是 {"error": "错误描述"}，不会影响其他信息的返回。
        """
        result: dict = {}

        # ---- Docker 统计 ----
        # 统计容器总数、运行数、停止数、镜像数
        try:
            client = get_docker_client_safe()
            containers = client.containers.list(all=True)
            images = client.images.list()
            running = sum(1 for c in containers if c.status == "running")
            result["docker"] = {
                "containers": {
                    "total": len(containers),
                    "running": running,
                    "stopped": len(containers) - running,
                },
                "images": len(images),
            }
            client.close()
        except Exception as e:
            result["docker"] = {"error": str(e)}

        # ---- Git 版本 ----
        # 获取当前代码的 Git 版本信息
        # search_parent_directories=False: 只查找当前目录是否为 git 仓库
        # 避免在挂载的主机文件系统中意外搜索到其他 git 仓库
        try:
            repo = git.Repo(os.getcwd(), search_parent_directories=False)
            head = repo.head.commit
            branch = "detached"  # 默认值：HEAD 处于 detached 状态
            if not repo.head.is_detached:
                branch = repo.active_branch.name
            result["git"] = {
                "branch": branch,
                "commit_hash": head.hexsha,
                "short_hash": head.hexsha[:7],
                "commit_message": head.message.strip(),
                "author": head.author.name,
                "date": datetime.fromtimestamp(head.committed_date).isoformat(),
            }
        except Exception:
            result["git"] = {"error": "无法获取 git 信息"}

        # ---- 系统资源 ----
        # CPU 使用率（interval=1 采样 1 秒获得准确值）
        # 内存总量、可用量、使用量、使用百分比
        try:
            cpu_percent = psutil.cpu_percent(interval=1)
            mem = psutil.virtual_memory()
            result["system"] = {
                "cpu": {
                    "percent": cpu_percent,
                    "count": psutil.cpu_count(),
                },
                "memory": {
                    "total": mem.total,
                    "available": mem.available,
                    "used": mem.used,
                    "percent": mem.percent,
                },
            }
        except Exception as e:
            result["system"] = {"error": str(e)}

        return result

    @server.tool(description="获取系统资源使用情况（CPU、内存、磁盘、GPU）。")
    def get_system_usage() -> dict:
        """获取实时系统资源使用情况。

        提供详细的资源使用数据，包括磁盘分区和 GPU 信息。
        与 get_system_info 的区别：
        - get_system_info: 聚合概览（Docker + Git + 系统）
        - get_system_usage: 详细资源数据（磁盘、GPU）

        返回:
            {
                "cpu": {"percent": 整体使用率, "count": 核心数},
                "memory": {"total": ..., "available": ..., "used": ..., "percent": ...},
                "disk": [{"device": ..., "mountpoint": ..., "total": ..., "used": ..., "free": ..., "percent": ...}],
                "gpu": [{"id": ..., "name": ..., "load": ..., "memory_total": ..., "temperature": ...}]
            }

        磁盘检测策略:
            - 如果设置了 HOST_FILESYSTEM_ROOT 且不为 "/"：只报告该路径的使用情况
            - 否则：遍历所有磁盘分区（过滤 loop 和 snap 设备）
            - 跳过无权限访问的分区

        GPU 检测:
            - 需要安装 GPUtil（pip install gputil）
            - 未安装时返回空列表，不影响其他数据
        """
        # ---- CPU ----
        # interval=1: 采样 1 秒获得准确的 CPU 使用率
        cpu_percent = psutil.cpu_percent(interval=1)
        mem = psutil.virtual_memory()

        # ---- 磁盘 ----
        disks: list[dict] = []
        host_fs = os.getenv("HOST_FILESYSTEM_ROOT", "/")
        try:
            if host_fs != "/" and os.path.exists(host_fs):
                # 容器化环境：通常 HOST_FILESYSTEM_ROOT=/hostfs
                # 只报告宿主文件系统使用情况
                usage = psutil.disk_usage(host_fs)
                disks.append(
                    {
                        "device": "host_root",
                        "mountpoint": host_fs,
                        "total": usage.total,
                        "used": usage.used,
                        "free": usage.free,
                        "percent": usage.percent,
                    }
                )
            else:
                # 非容器化环境：遍历所有分区
                for partition in psutil.disk_partitions():
                    try:
                        # 过滤虚拟设备
                        if "loop" in partition.device or "snap" in partition.mountpoint:
                            continue
                        usage = psutil.disk_usage(partition.mountpoint)
                        disks.append(
                            {
                                "device": partition.device,
                                "mountpoint": partition.mountpoint,
                                "fstype": partition.fstype,
                                "total": usage.total,
                                "used": usage.used,
                                "free": usage.free,
                                "percent": usage.percent,
                            }
                        )
                    except (PermissionError, OSError):
                        # 跳过无权限访问的分区（如 /run/user/1000/doc）
                        continue
        except Exception:
            pass  # 磁盘信息获取失败不影响其他信息

        # ---- GPU ----
        # GPUtil 提供 NVIDIA GPU 监控（通过 nvidia-smi）
        # 如果没有 NVIDIA GPU 或未安装驱动，GPUtil.getGPUs() 返回空列表
        gpus: list[dict] = []
        if GPUtil:
            try:
                for gpu in GPUtil.getGPUs():
                    gpus.append(
                        {
                            "id": gpu.id,
                            "name": gpu.name,
                            "load": gpu.load * 100,  # 转换为百分比（原始值 0-1）
                            "memory_total": gpu.memoryTotal,  # MB
                            "memory_used": gpu.memoryUsed,  # MB
                            "memory_free": gpu.memoryFree,  # MB
                            "temperature": gpu.temperature,  # 摄氏度
                        }
                    )
            except Exception:
                pass

        return {
            "cpu": {"percent": cpu_percent, "count": psutil.cpu_count()},
            "memory": {
                "total": mem.total,
                "available": mem.available,
                "used": mem.used,
                "percent": mem.percent,
            },
            "disk": disks,
            "gpu": gpus,
        }

    @server.tool(description="列出所有 Docker Compose 项目（堆栈）及其容器数量。")
    def list_stacks() -> list[dict]:
        """列出所有 Docker Compose 项目（堆栈）。

        通过检查容器的 com.docker.compose.project 标签来识别 Compose 项目。
        相当于 docker compose ls。

        工作原理:
            遍历所有容器的 labels，收集 "com.docker.compose.project" 标签的值，
            按项目名分组统计容器数量。

        返回:
            [{"name": "项目名", "container_count": N}, ...]
            按项目名称字母顺序排序

        局限性:
            仅检测通过 docker compose 启动的容器（带有特定 label），
            Docker Swarm 项目使用不同的标签（见 get_stack_containers）。
        """
        client = get_docker_client_safe()
        try:
            containers = client.containers.list(all=True)
            stacks: dict[str, int] = {}
            for c in containers:
                labels = c.labels or {}
                stack_name = labels.get("com.docker.compose.project")
                if stack_name:
                    stacks[stack_name] = stacks.get(stack_name, 0) + 1
            return [
                {"name": k, "container_count": v} for k, v in sorted(stacks.items())
            ]
        finally:
            client.close()

    @server.tool(description="获取属于指定堆栈的所有容器。")
    def get_stack_containers(stack_name: str) -> list[dict]:
        """获取指定 Docker Compose 项目的所有容器。

        参数:
            stack_name: Compose 项目名称（即 docker-compose.yml 中
                        的 COMPOSE_PROJECT_NAME 或目录名）

        返回:
            容器摘要信息列表（与 list_containers(summary=True) 格式相同）

        查找策略（两级回退）：
        1. 首先查找 com.docker.compose.project={stack_name} 标签的容器
        2. 如果第一步没找到，尝试 com.docker.stack.namespace={stack_name}
           （Docker Swarm / docker stack deploy 使用的标签）

        返回格式说明:
            使用 process_container_summary() 处理每个容器，包含：
            id, name, image, status, ports, networks, created, labels, is_self
        """
        client = get_docker_client_safe()
        self_id = get_current_container_id()
        try:
            # 第 1 步：通过 docker compose 标签查找
            filters = {"label": f"com.docker.compose.project={stack_name}"}
            containers = client.containers.list(all=True, filters=filters)

            # 第 2 步：如果没找到，尝试 docker stack 标签
            if not containers:
                filters_swarm = {"label": f"com.docker.stack.namespace={stack_name}"}
                containers = client.containers.list(all=True, filters=filters_swarm)

            return [process_container_summary(c, self_id) for c in containers]
        finally:
            client.close()

    # ================================================================
    # 项目工具（Project Tools）
    # 提供项目的完整管理：CRUD、文件编辑、镜像构建、compose 启停。
    # ================================================================

    # -- 默认模板（与 app/routers/projects.py 保持一致）-----------------

    _DEFAULT_DOCKERFILE = """\
FROM alpine:latest

# 设置工作目录
WORKDIR /app

# 复制文件（根据需要修改）
# COPY . .

# 运行命令（根据需要修改）
# CMD ["echo", "Hello World"]
"""

    _DEFAULT_COMPOSE_YAML = """\
version: '3.8'

services:
  app:
    build: .
    # ports:
    #   - "8080:80"
    # volumes:
    #   - ./data:/app/data
    # environment:
    #   - NODE_ENV=production
"""

    # -- 辅助函数 --------------------------------------------------------

    def _project_dir(project_id: str) -> pathlib.Path:
        """返回项目文件存储目录。"""
        return pathlib.Path(PROJECTS_DIR) / project_id

    def _model_to_dict(p: ProjectModel) -> dict:
        """SQLAlchemy 模型 → API 字典。"""
        return {
            "id": p.id,
            "name": p.name,
            "description": p.description,
            "status": p.status,
            "createdAt": p.created_at.isoformat() if p.created_at else None,
            "updatedAt": p.updated_at.isoformat() if p.updated_at else None,
        }

    # -- 项目 CRUD -------------------------------------------------------

    @server.tool(description="列出所有项目，按更新时间倒序排列。")
    def list_projects() -> list[dict]:
        """列出所有项目。

        返回每个项目的基本信息，包括 id、名称、描述、状态和创建/更新时间。
        项目状态: idle（空闲）| building（构建中）| running（运行中）| failed（失败）。

        返回:
            项目字典列表，按 updated_at 降序排列。
        """
        with get_db_session() as db:
            projects = (
                db.query(ProjectModel).order_by(ProjectModel.updated_at.desc()).all()
            )
            return [_model_to_dict(p) for p in projects]

    @server.tool(description="通过项目 ID 获取项目详细信息。")
    def get_project(project_id: str) -> dict:
        """获取单个项目的完整详情。

        参数:
            project_id: 项目 ID（如 "proj_a1b2c3d4e5f6"）

        返回:
            项目完整信息字典（id、name、description、status、时间戳）

        异常:
            RuntimeError: 项目不存在时抛出
        """
        with get_db_session() as db:
            project = (
                db.query(ProjectModel).filter(ProjectModel.id == project_id).first()
            )
            if not project:
                raise RuntimeError(f"未找到项目：{project_id}")
            return _model_to_dict(project)

    @server.tool(
        description="创建新项目，自动生成默认 Dockerfile 和 docker-compose.yaml 模板。"
    )
    def create_project(name: str, description: str | None = None) -> dict:
        """创建新项目。

        创建项目的同时会在文件系统中生成默认的 Dockerfile 和
        docker-compose.yaml 模板文件，方便用户在此基础上修改。

        参数:
            name: 项目名称（必须唯一，1-128 字符）
            description: 项目描述（可选，最多 512 字符）

        返回:
            新创建的项目信息字典

        异常:
            RuntimeError: 项目名称已存在或参数无效时抛出
        """
        if not name or not name.strip():
            raise RuntimeError("项目名称为必填项")
        if len(name) > 128:
            raise RuntimeError("项目名称不能超过 128 个字符")

        with get_db_session() as db:
            existing = (
                db.query(ProjectModel).filter(ProjectModel.name == name.strip()).first()
            )
            if existing:
                raise RuntimeError(f"项目名称已存在：{name}")

            project_id = f"proj_{uuid.uuid4().hex[:12]}"
            now = datetime.utcnow()

            project = ProjectModel(
                id=project_id,
                name=name.strip(),
                description=description.strip() if description else None,
                status="idle",
                created_at=now,
                updated_at=now,
            )
            db.add(project)
            db.commit()
            db.refresh(project)

            # ---- 创建项目目录和默认文件 ----
            project_dir = _project_dir(project_id)
            project_dir.mkdir(parents=True, exist_ok=True)
            (project_dir / "Dockerfile").write_text(
                _DEFAULT_DOCKERFILE, encoding="utf-8"
            )
            (project_dir / "docker-compose.yaml").write_text(
                _DEFAULT_COMPOSE_YAML, encoding="utf-8"
            )

            return _model_to_dict(project)

    @server.tool(description="删除项目及其关联的所有文件。")
    def delete_project(project_id: str) -> dict:
        """删除项目。

        删除操作会同时：
        1. 尝试停止并移除项目的 compose 容器（docker compose down --volumes）
        2. 从数据库删除项目记录
        3. 删除项目目录下的所有文件

        参数:
            project_id: 项目 ID

        返回:
            {"status": "deleted"}

        异常:
            RuntimeError: 项目不存在或正在构建中无法删除时抛出
        """
        with get_db_session() as db:
            project = (
                db.query(ProjectModel).filter(ProjectModel.id == project_id).first()
            )
            if not project:
                raise RuntimeError(f"未找到项目：{project_id}")
            if project.status == "building":
                raise RuntimeError("项目正在构建中，无法删除")

            # 尝试 compose down
            compose_file = _project_dir(project_id) / "docker-compose.yaml"
            if compose_file.exists():
                try:
                    subprocess.run(
                        [
                            "docker",
                            "compose",
                            "-f",
                            str(compose_file),
                            "-p",
                            f"mp_{project_id}",
                            "down",
                            "--volumes",
                        ],
                        capture_output=True,
                        timeout=30,
                    )
                except Exception:
                    pass

            db.delete(project)
            db.commit()

            # 删除项目目录
            project_dir = _project_dir(project_id)
            if project_dir.exists():
                try:
                    shutil.rmtree(str(project_dir))
                except OSError:
                    pass

        return {"status": "deleted"}

    # -- 文件操作 --------------------------------------------------------

    @server.tool(description="获取项目文件内容（Dockerfile 或 docker-compose.yaml）。")
    def get_project_file(project_id: str, filename: str) -> dict:
        """读取项目配置文件的内容。

        参数:
            project_id: 项目 ID
            filename: 文件名，必须是 "Dockerfile" 或 "docker-compose.yaml"

        返回:
            {"filename": "Dockerfile", "content": "文件内容字符串"}

        异常:
            RuntimeError: 项目不存在、文件名不支持或文件不存在时抛出
        """
        allowed = {"Dockerfile", "docker-compose.yaml"}
        if filename not in allowed:
            raise RuntimeError(f"不支持的文件名: {filename}，仅支持 {allowed}")

        with get_db_session() as db:
            project = (
                db.query(ProjectModel).filter(ProjectModel.id == project_id).first()
            )
            if not project:
                raise RuntimeError(f"未找到项目：{project_id}")

        file_path = _project_dir(project_id) / filename
        if not file_path.exists():
            raise RuntimeError(f"文件 {filename} 不存在")

        return {
            "filename": filename,
            "content": file_path.read_text(encoding="utf-8"),
        }

    @server.tool(description="更新项目文件内容（Dockerfile 或 docker-compose.yaml）。")
    def update_project_file(project_id: str, filename: str, content: str) -> dict:
        """更新项目配置文件的内容。

        参数:
            project_id: 项目 ID
            filename: 文件名，必须是 "Dockerfile" 或 "docker-compose.yaml"
            content: 新的文件内容（完整替换）

        返回:
            {"filename": "Dockerfile", "status": "saved"}

        异常:
            RuntimeError: 项目不存在、文件名不支持或 content 为空时抛出
        """
        allowed = {"Dockerfile", "docker-compose.yaml"}
        if filename not in allowed:
            raise RuntimeError(f"不支持的文件名: {filename}，仅支持 {allowed}")
        if content is None:
            raise RuntimeError("content 字段为必填项")

        with get_db_session() as db:
            project = (
                db.query(ProjectModel).filter(ProjectModel.id == project_id).first()
            )
            if not project:
                raise RuntimeError(f"未找到项目：{project_id}")

            file_path = _project_dir(project_id) / filename
            file_path.write_text(content, encoding="utf-8")
            project.updated_at = datetime.utcnow()
            db.commit()

        return {"filename": filename, "status": "saved"}

    # -- 构建操作 --------------------------------------------------------

    @server.tool(description="触发 Docker 镜像构建（同步模式，返回完整构建日志）。")
    def build_project(project_id: str) -> dict:
        """触发 Docker 镜像构建。

        MCP 环境下的构建是同步的——工具会等待构建完成并返回完整日志。
        这与 HTTP API 的异步+WebSocket 模式不同。

        构建过程:
        1. 检查 Dockerfile 是否存在且非空
        2. 更新项目状态为 building
        3. 执行 docker build
        4. 构建成功 → 状态设为 idle
        5. 构建失败 → 状态设为 failed

        参数:
            project_id: 项目 ID

        返回:
            {
                "status": "success" | "failed",
                "imageId": "构建成功后的镜像 ID（失败时为 None）",
                "logs": ["逐行构建日志", ...]
            }

        异常:
            RuntimeError: 项目不存在、正在构建中、Dockerfile 问题
        """
        project_dir = _project_dir(project_id)

        with get_db_session() as db:
            project = (
                db.query(ProjectModel).filter(ProjectModel.id == project_id).first()
            )
            if not project:
                raise RuntimeError(f"未找到项目：{project_id}")
            if project.status == "building":
                raise RuntimeError("项目正在构建中")

            # 检查 Dockerfile
            dockerfile_path = project_dir / "Dockerfile"
            if not dockerfile_path.exists():
                raise RuntimeError("Dockerfile 不存在")
            if not dockerfile_path.read_text(encoding="utf-8").strip():
                raise RuntimeError("Dockerfile 为空")

            # 更新状态为 building
            project.status = "building"
            project.updated_at = datetime.utcnow()
            db.commit()

        client = get_docker_client_safe()
        logs: list[str] = []
        image_id: str | None = None
        build_success = False

        try:
            for chunk in client.api.build(
                path=str(project_dir),
                dockerfile="Dockerfile",
                tag=f"mobile_portainer_proj_{project_id}:latest",
                rm=True,
                decode=True,
            ):
                if "stream" in chunk:
                    logs.append(chunk["stream"].rstrip("\n"))
                elif "status" in chunk:
                    logs.append(f"[STATUS] {chunk['status']}")
                elif "error" in chunk:
                    logs.append(f"[ERROR] {chunk['error']}")
                elif "message" in chunk:
                    logs.append(f"[ERROR] {chunk['message']}")

            # 构建成功（没有抛出异常）
            build_success = True
            # 尝试从最新的镜像中获取 ID
            try:
                img = client.images.get(f"mobile_portainer_proj_{project_id}:latest")
                image_id = img.id
            except Exception:
                pass
        except Exception as exc:
            logs.append(f"[ERROR] 构建失败: {exc}")
            build_success = False
        finally:
            client.close()

        # 更新最终状态
        with get_db_session() as db:
            project = (
                db.query(ProjectModel).filter(ProjectModel.id == project_id).first()
            )
            if project:
                project.status = "idle" if build_success else "failed"
                project.updated_at = datetime.utcnow()
                db.commit()

        return {
            "status": "success" if build_success else "failed",
            "imageId": image_id,
            "logs": logs,
        }

    # -- Compose 操作 ----------------------------------------------------

    @server.tool(description="启动项目容器（docker compose up -d --build）。")
    def project_up(project_id: str) -> dict:
        """启动项目容器（docker compose up -d --build）。

        对项目目录执行 docker compose up -d --build，启动所有服务容器。
        项目状态更新为 running。

        参数:
            project_id: 项目 ID

        返回:
            {
                "status": "started",
                "containerIds": ["容器 ID 列表"],
                "message": "Containers started successfully"
            }

        异常:
            RuntimeError: 项目不存在、正在构建中、compose 文件问题或启动失败
        """
        project_dir = _project_dir(project_id)
        compose_file = project_dir / "docker-compose.yaml"

        with get_db_session() as db:
            project = (
                db.query(ProjectModel).filter(ProjectModel.id == project_id).first()
            )
            if not project:
                raise RuntimeError(f"未找到项目：{project_id}")
            if project.status == "building":
                raise RuntimeError("项目正在构建中")

        if not compose_file.exists():
            raise RuntimeError("docker-compose.yaml 不存在")
        if not compose_file.read_text(encoding="utf-8").strip():
            raise RuntimeError("docker-compose.yaml 为空")

        compose_name = f"mp_{project_id}"

        try:
            result = subprocess.run(
                [
                    "docker",
                    "compose",
                    "-f",
                    str(compose_file),
                    "-p",
                    compose_name,
                    "up",
                    "-d",
                    "--build",
                ],
                capture_output=True,
                text=True,
                timeout=120,
                cwd=str(project_dir),
            )
            if result.returncode != 0:
                raise RuntimeError(f"启动失败: {result.stderr or result.stdout}")
        except subprocess.TimeoutExpired:
            raise RuntimeError("启动超时（120s）")
        except FileNotFoundError:
            raise RuntimeError(
                "未找到 docker compose 命令，请确保 Docker Compose 已安装"
            )
        except RuntimeError:
            raise
        except Exception as e:
            raise RuntimeError(f"启动失败: {e}")

        # 获取容器 ID 列表
        container_ids: list[str] = []
        try:
            client = get_docker_client_safe()
            containers = client.containers.list(
                all=True,
                filters={"label": f"com.docker.compose.project={compose_name}"},
            )
            container_ids = [c.id for c in containers]
            client.close()
        except Exception:
            pass

        with get_db_session() as db:
            project = (
                db.query(ProjectModel).filter(ProjectModel.id == project_id).first()
            )
            if project:
                project.status = "running"
                project.updated_at = datetime.utcnow()
                db.commit()

        return {
            "status": "started",
            "containerIds": container_ids,
            "message": "Containers started successfully",
        }

    @server.tool(description="停止项目容器（docker compose down）。")
    def project_down(project_id: str) -> dict:
        """停止项目容器（docker compose down）。

        对项目目录执行 docker compose down，停止并移除所有服务容器。
        项目状态更新为 idle。

        参数:
            project_id: 项目 ID

        返回:
            {"status": "stopped", "message": "Containers stopped successfully"}

        异常:
            RuntimeError: 项目不存在时抛出
        """
        with get_db_session() as db:
            project = (
                db.query(ProjectModel).filter(ProjectModel.id == project_id).first()
            )
            if not project:
                raise RuntimeError(f"未找到项目：{project_id}")

        compose_file = _project_dir(project_id) / "docker-compose.yaml"
        compose_name = f"mp_{project_id}"

        if compose_file.exists():
            try:
                subprocess.run(
                    [
                        "docker",
                        "compose",
                        "-f",
                        str(compose_file),
                        "-p",
                        compose_name,
                        "down",
                    ],
                    capture_output=True,
                    text=True,
                    timeout=60,
                    cwd=str(_project_dir(project_id)),
                )
            except Exception:
                pass

        with get_db_session() as db:
            project = (
                db.query(ProjectModel).filter(ProjectModel.id == project_id).first()
            )
            if project:
                project.status = "idle"
                project.updated_at = datetime.utcnow()
                db.commit()

        return {
            "status": "stopped",
            "message": "Containers stopped successfully",
        }
