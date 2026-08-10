"""容器升级功能：判断镜像是否为最新版本、重建容器（端口/挂载/环境变量等参数不变）。

Docker 本身没有"更新容器"API，升级采用与 Portainer 等管理工具一致的重建方案：
1. 解析容器镜像引用（name/tag）
2. docker pull 拉取最新镜像（增量拉取，幂等，不会重复下载已存在的层）
3. 对比容器创建时镜像 Id（attrs["ImageID"]）与拉取后最新镜像 Id（attrs["Id"]）
4. 若不同 → 从容器 attrs 提取完整配置重建容器：
   临时名创建新容器（创建失败则旧容器保持原样）→ 停止并删除旧容器（保留卷）→
   新容器改回原名 → 启动
"""

import uuid
from typing import Dict, Tuple

DEFAULT_NETWORKS = {"bridge", "host", "none", "default"}


class ContainerNotFoundError(Exception):
    """容器不存在或无法访问。"""


# ---------- 镜像引用解析 ----------

def parse_image_ref(image_ref: str) -> Tuple[str, str]:
    """解析镜像引用为 (name, tag)，无 tag 时默认 latest。

    处理 registry 端口（registry:5000/foo 的 :5000 不是 tag）与 digest 形式
    （ubuntu@sha256:xxx 取 @ 前部分）。
    """
    if not image_ref:
        raise ValueError("镜像引用不能为空")
    # digest 形式：name@sha256:...，取 digest 前部分，tag 默认 latest
    if "@" in image_ref:
        return (image_ref.split("@")[0], "latest")
    # 仅在最后一段（最后一个 / 之后）查找 :，避免误判 registry 端口
    last_segment = image_ref.rsplit("/", 1)[-1]
    if ":" in last_segment:
        name, tag = image_ref.rsplit(":", 1)
        return (name, tag)
    return (image_ref, "latest")


def _repo_digest(repo_digests):
    """从 RepoDigests 列表（["repo@sha256:xxx"]）提取 sha256 摘要，无则返回 None。"""
    for d in repo_digests or []:
        if "@sha256:" in d:
            return "sha256:" + d.split("@sha256:", 1)[1]
    return None


def _resolve_create_image(config_image: str) -> str:
    """digest 形式的镜像引用在重建时改用 name:tag，避免仍指向旧 digest。"""
    if "@" in config_image:
        name, tag = parse_image_ref(config_image)
        return f"{name}:{tag}"
    return config_image


# ---------- 从容器 attrs 构造重建参数 ----------

def build_create_params(attrs: Dict) -> Dict:
    """从容器 attrs（docker inspect）构造 docker-py create 参数。

    保留：镜像、环境变量、命令/入口、工作目录、用户、主机名、标签、
    端口绑定（含 HostIp/随机端口/仅 expose）、挂载（含 ro 标志）、重启策略、
    devices、cap_add/drop、网络（自定义网络别名/固定 IP）、healthcheck、
    停止信号/超时、以及常见资源限制（透传 HostConfig 同名键）。
    """
    config = attrs.get("Config") or {}
    host_config = attrs.get("HostConfig") or {}
    network_settings = attrs.get("NetworkSettings") or {}

    image = config.get("Image")
    if not image:
        raise ValueError("容器缺少镜像配置（Config.Image），无法重建")

    params: Dict = {"image": image}

    # 环境变量：["K=V", ...] → dict
    env = {}
    for item in config.get("Env") or []:
        if "=" in item:
            k, v = item.split("=", 1)
            env[k] = v
    params["environment"] = env

    # 命令/入口/工作目录/用户/主机名（None 则沿用镜像默认）
    params["command"] = config.get("Cmd")
    params["entrypoint"] = config.get("Entrypoint")
    params["working_dir"] = config.get("WorkingDir")
    params["user"] = config.get("User")
    params["hostname"] = config.get("Hostname")

    # 标签（保留 com.docker.compose.* 等关联标签）
    params["labels"] = dict(config.get("Labels") or {})

    # 端口：ExposedPorts 声明 + PortBindings 绑定 → docker-py ports 参数
    exposed = config.get("ExposedPorts") or {}
    bindings = host_config.get("PortBindings") or {}
    ports = {}
    for container_port in exposed:
        if container_port in bindings:
            entries = [
                (b.get("HostIp") or "", b.get("HostPort") or None)
                for b in bindings[container_port]
            ]
            ports[container_port] = entries if len(entries) > 1 else entries[0]
        else:
            # 仅声明未绑定（expose）→ None 表示随机/仅暴露
            ports[container_port] = None
    params["ports"] = ports

    # 挂载（binds 列表原样保留，含 :ro 等标志）
    params["binds"] = list(host_config.get("Binds") or [])

    # 重启策略
    restart_policy = host_config.get("RestartPolicy") or {}
    if restart_policy.get("Name"):
        policy = {"Name": restart_policy["Name"]}
        if restart_policy.get("MaximumRetryCount") is not None:
            policy["MaximumRetryCount"] = restart_policy["MaximumRetryCount"]
        params["restart_policy"] = policy

    # devices：attrs 的 dict 列表 → docker-py 的 "host:cont:perm" 字符串列表
    devices = host_config.get("Devices") or []
    params["devices"] = [
        f"{d.get('PathOnHost')}:{d.get('PathInContainer')}:"
        f"{d.get('CgroupPermissions') or 'rwm'}"
        for d in devices
    ]
    params["cap_add"] = list(host_config.get("CapAdd") or [])
    params["cap_drop"] = list(host_config.get("CapDrop") or [])

    # 网络：自定义网络（含别名/固定 IP）→ networks 参数；默认网络 → network_mode
    network_mode = host_config.get("NetworkMode")
    if network_mode and network_mode.startswith("container:"):
        raise ValueError(
            f"容器的网络模式为 {network_mode}，依赖其他容器，升级后该网络会失效，不支持升级"
        )
    networks = {}
    for net_name, conf in (network_settings.get("Networks") or {}).items():
        if net_name in DEFAULT_NETWORKS:
            continue
        entry = {}
        aliases = conf.get("Aliases") or []
        if aliases:
            entry["aliases"] = aliases
        ipam = conf.get("IPAMConfig") or {}
        if ipam:
            entry["ipam"] = ipam
        networks[net_name] = entry
    if networks:
        params["networks"] = networks
    elif network_mode:
        params["network_mode"] = network_mode

    # 健康检查：attrs 中 Interval/Timeout/StartPeriod 为纳秒，docker-py 参数为秒
    healthcheck = config.get("Healthcheck")
    if healthcheck:
        hc = {}
        if healthcheck.get("Test"):
            hc["test"] = healthcheck["Test"]
        for src, dst in (
            ("Interval", "interval"),
            ("Timeout", "timeout"),
            ("StartPeriod", "start_period"),
        ):
            val = healthcheck.get(src)
            if val is not None:
                hc[dst] = val // 1_000_000_000
        if healthcheck.get("Retries") is not None:
            hc["retries"] = healthcheck["Retries"]
        params["healthcheck"] = hc

    params["stop_signal"] = config.get("StopSignal")

    # 透传 HostConfig 同名键（资源限制/日志/安全等），跳过空值与默认值
    passthrough_keys = [
        "privileged", "auto_remove", "read_only", "ipc_mode", "uts_mode",
        "userns_mode", "pid_mode", "security_opt", "log_config", "volumes_from",
        "dns", "dns_search", "extra_hosts", "tmpfs", "sysctls", "memory",
        "memory_swap", "memory_reservation", "cpuset_cpus", "cpu_shares",
        "cpu_quota", "cpu_period", "nano_cpus", "pids_limit", "blkio_weight",
        "oom_kill_disable", "shm_size", "init", "group_add", "ulimits",
    ]
    for key in passthrough_keys:
        val = host_config.get(key)
        if val is None:
            continue
        if isinstance(val, (dict, list)) and not val:
            continue
        if val == 0 or val == "" or val is False:
            continue
        params[key] = val

    return params


# ---------- 检查更新 ----------

def _get_container_or_raise(client, container_id: str):
    try:
        return client.containers.get(container_id)
    except ContainerNotFoundError:
        raise
    except Exception as e:
        raise ContainerNotFoundError(f"无法获取容器 {container_id}: {e}")


def check_container_update(client, container_id: str) -> Dict:
    """拉取镜像最新版本并判断是否有更新。

    返回: {"status": "update_available"|"up_to_date"|"unknown",
           "current_image", "current_digest", "latest_digest", "message"}
    """
    container = _get_container_or_raise(client, container_id)
    attrs = container.attrs
    config_image = (attrs.get("Config") or {}).get("Image")
    if not config_image:
        raise ValueError("容器缺少镜像配置（Config.Image），无法检查更新")

    name, tag = parse_image_ref(config_image)
    # 拉取最新镜像（增量拉取，幂等）
    client.images.pull(name, tag=tag)
    latest = client.images.get(f"{name}:{tag}")

    # 旧 digest 优先取容器创建时的镜像 Id（ImageID），缺失则回退 RepoDigests
    old_digest = attrs.get("ImageID") or _repo_digest(attrs.get("RepoDigests"))
    new_digest = latest.attrs.get("Id") or _repo_digest(latest.attrs.get("RepoDigests"))

    if old_digest and new_digest:
        if old_digest == new_digest:
            status, message = "up_to_date", "当前已是最新版本"
        else:
            status, message = "update_available", "发现新版本镜像"
    else:
        status, message = "unknown", "无法对比镜像摘要（容器或镜像缺少 digest 信息）"

    return {
        "status": status,
        "current_image": config_image,
        "current_digest": old_digest,
        "latest_digest": new_digest,
        "message": message,
    }


# ---------- 升级容器 ----------

def upgrade_container(client, container_id: str) -> Dict:
    """拉取最新镜像并重建容器（保留端口/挂载/环境变量等参数）。

    流程：校验 → pull → digest 对比（已最新则直接返回）→ 临时名创建新容器
    （失败则旧容器保持原样）→ 停止并删除旧容器（保留卷）→ 新容器改回原名 → 启动。
    """
    container = _get_container_or_raise(client, container_id)
    attrs = container.attrs
    config_image = (attrs.get("Config") or {}).get("Image")
    if not config_image:
        raise ValueError("容器缺少镜像配置（Config.Image），无法升级")

    # 先校验不可升级的配置（如依赖其他容器的网络模式），避免白拉镜像
    network_mode = (attrs.get("HostConfig") or {}).get("NetworkMode")
    if network_mode and network_mode.startswith("container:"):
        raise ValueError(
            f"容器的网络模式为 {network_mode}，依赖其他容器，升级后该网络会失效，不支持升级"
        )

    name, tag = parse_image_ref(config_image)
    # 1. 拉取最新镜像
    client.images.pull(name, tag=tag)

    # 2. 对比 digest：相同则已是最新，无需重建
    latest = client.images.get(f"{name}:{tag}")
    old_digest = attrs.get("ImageID") or _repo_digest(attrs.get("RepoDigests"))
    new_digest = latest.attrs.get("Id") or _repo_digest(latest.attrs.get("RepoDigests"))
    if old_digest and new_digest and old_digest == new_digest:
        return {
            "status": "up_to_date",
            "current_image": config_image,
            "message": "当前已是最新版本，无需升级",
        }

    # 3. 构造重建参数（含端口/挂载/环境变量等），digest 形式引用改用 name:tag
    params = build_create_params(attrs)
    params["image"] = _resolve_create_image(config_image)

    # 4. 临时名创建新容器（创建失败则旧容器保持原样，安全返回）
    tmp_name = f"{container.name}-upgrading-{uuid.uuid4().hex[:8]}"
    new_container = client.containers.create(name=tmp_name, **params)

    try:
        # 5. 停止并删除旧容器（v=False 保留匿名卷，命名卷/绑定挂载不受影响）
        status = str(container.status).lower()
        if status == "paused":
            container.unpause()
        if status in ("running", "paused", "restarting"):
            stop_timeout = (attrs.get("HostConfig") or {}).get("StopTimeout") or 10
            container.stop(timeout=stop_timeout)
        container.remove(force=True, v=False)

        # 6. 新容器改回原名并启动
        new_container.rename(container.name)
        new_container.start()
    except Exception:
        # 尽力回滚：删除半成品新容器，避免残留（旧容器卷仍保留）
        try:
            new_container.remove(force=True, v=False)
        except Exception:
            pass
        raise

    return {
        "status": "upgraded",
        "id": new_container.id,
        "short_id": new_container.short_id,
        "name": container.name,
        "image": f"{name}:{tag}",
        "old_digest": old_digest,
        "new_digest": new_digest,
        "message": "容器已升级到最新镜像",
    }
