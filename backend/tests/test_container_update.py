"""容器升级功能测试：镜像最新性判断 + 容器重建（保留端口/挂载/环境变量等参数）。

覆盖：
- parse_image_ref：普通/带 tag/带 registry 端口/digest 形式/空值
- build_create_params：端口（含 IP/随机/仅 expose）、env、binds、restart_policy、
  networks（别名/固定 IP）、host/none 网络模式、container: 模式拒绝、healthcheck 转换
- check_container_update：有更新/无更新/无 ImageID 走 RepoDigests/都无→unknown/pull 失败
- upgrade_container：正常升级（临时名 create→stop→remove→rename→start）/已最新/旧容器
  停止时不 stop/create 失败旧容器不动/container: 模式拒绝
"""

import uuid
from unittest.mock import MagicMock, patch

import pytest

from app.core.container_update import (
    build_create_params,
    check_container_update,
    parse_image_ref,
    upgrade_container,
)
from app.db.models import APIKeyModel


# ---------- 测试数据：真实 docker inspect 形状 ----------

def make_attrs(**overrides):
    """构造一份完整的容器 attrs（docker inspect 形状），可覆盖关键字段。"""
    attrs = {
        "Id": "sha256:abcdef123456",
        "ImageID": "sha256:old-digest-111",
        "Config": {
            "Image": "nginx:1.25",
            "Env": ["NGINX_PORT=80", "DEBUG=true"],
            "Cmd": ["nginx", "-g", "daemon off;"],
            "Entrypoint": ["/docker-entrypoint.sh"],
            "WorkingDir": "/app",
            "User": "1000:1000",
            "Hostname": "my-nginx",
            "Labels": {"com.docker.compose.project": "mp_1", "app": "web"},
            "ExposedPorts": {"80/tcp": {}, "443/tcp": {}},
            "Healthcheck": {
                "Test": ["CMD-SHELL", "curl -f http://localhost/ || exit 1"],
                "Interval": 30000000000,  # 30s（纳秒）
                "Timeout": 3000000000,    # 3s（纳秒）
                "Retries": 3,
                "StartPeriod": 5000000000,  # 5s（纳秒）
            },
            "StopSignal": "SIGTERM",
        },
        "HostConfig": {
            "Binds": ["/data:/data:ro", "vol1:/etc/vol1"],
            "PortBindings": {
                "80/tcp": [{"HostIp": "", "HostPort": "8080"}],
                "443/tcp": [{"HostIp": "127.0.0.1", "HostPort": "8443"}],
            },
            "RestartPolicy": {"Name": "unless-stopped", "MaximumRetryCount": 0},
            "Privileged": False,
            "NetworkMode": "mp_1_default",
            "Devices": [
                {
                    "PathOnHost": "/dev/sda",
                    "PathInContainer": "/dev/sda",
                    "CgroupPermissions": "rwm",
                }
            ],
            "CapAdd": ["NET_ADMIN"],
            "CapDrop": ["ALL"],
            "AutoRemove": False,
            "LogConfig": {"Type": "json-file", "Config": {}},
            "Memory": 0,
            "CpuShares": 0,
        },
        "NetworkSettings": {
            "Networks": {
                "mp_1_default": {
                    "Aliases": ["web"],
                    "IPAMConfig": {"IPv4Address": "172.20.0.5"},
                }
            }
        },
    }
    for key, value in overrides.items():
        # 支持 "Config.Image" 这种点路径覆盖
        if "." in key:
            section, field = key.split(".", 1)
            attrs[section][field] = value
        else:
            attrs[key] = value
    return attrs


def make_container(attrs=None, status="running"):
    """构造一个模拟容器对象。"""
    container = MagicMock()
    container.attrs = attrs or make_attrs()
    container.status = status
    container.name = "my-nginx"
    return container


def make_client(container=None, latest_image_id="sha256:new-digest-222", image=None):
    """构造模拟 docker client：images.get 返回最新镜像（可自定义 Id）。"""
    client = MagicMock()
    if container is not None:
        client.containers.get.return_value = container
    if image is None:
        image = MagicMock()
        image.attrs = {"Id": latest_image_id}
    client.images.get.return_value = image
    return client


# ---------- parse_image_ref ----------

class TestParseImageRef:
    def test_plain_name_defaults_to_latest(self):
        """无 tag 的镜像名默认 latest。"""
        assert parse_image_ref("nginx") == ("nginx", "latest")

    def test_name_with_tag(self):
        """普通 name:tag。"""
        assert parse_image_ref("nginx:1.25") == ("nginx", "1.25")

    def test_registry_path_with_tag(self):
        """带 registry 路径与 tag。"""
        assert parse_image_ref("registry.example.com/foo/bar:1.0") == (
            "registry.example.com/foo/bar",
            "1.0",
        )

    def test_registry_with_port_is_not_tag(self):
        """registry:5000 的端口不应被当作 tag。"""
        assert parse_image_ref("registry:5000/foo") == ("registry:5000/foo", "latest")

    def test_digest_form_splits_name(self):
        """image@sha256:... 形式：取 digest 前的部分，tag 默认 latest。"""
        assert parse_image_ref("ubuntu@sha256:abc123") == ("ubuntu", "latest")

    def test_empty_ref_raises(self):
        """空镜像引用应报错。"""
        with pytest.raises(ValueError):
            parse_image_ref("")
        with pytest.raises(ValueError):
            parse_image_ref(None)


# ---------- build_create_params ----------

class TestBuildCreateParams:
    def test_full_attrs_preserves_all_core_params(self):
        """端口/环境变量/挂载/重启策略/标签/用户/工作目录/命令等应完整保留。"""
        params = build_create_params(make_attrs())

        assert params["image"] == "nginx:1.25"
        # 环境变量列表 → dict
        assert params["environment"] == {"NGINX_PORT": "80", "DEBUG": "true"}
        # 命令与入口
        assert params["command"] == ["nginx", "-g", "daemon off;"]
        assert params["entrypoint"] == ["/docker-entrypoint.sh"]
        assert params["working_dir"] == "/app"
        assert params["user"] == "1000:1000"
        assert params["hostname"] == "my-nginx"
        # 标签保留（compose 关联等）
        assert params["labels"] == {
            "com.docker.compose.project": "mp_1",
            "app": "web",
        }
        # 挂载（binds 列表原样保留，含 :ro 标志）
        assert params["binds"] == ["/data:/data:ro", "vol1:/etc/vol1"]
        # 重启策略
        assert params["restart_policy"] == {
            "Name": "unless-stopped",
            "MaximumRetryCount": 0,
        }
        # devices / capabilities
        assert params["devices"] == ["/dev/sda:/dev/sda:rwm"]
        assert params["cap_add"] == ["NET_ADMIN"]
        assert params["cap_drop"] == ["ALL"]
        # 停止信号
        assert params["stop_signal"] == "SIGTERM"

    def test_port_bindings_converted_with_ip(self):
        """端口绑定应转换为 docker-py 格式，含 HostIp 与随机端口。"""
        attrs = make_attrs(
            **{
                "HostConfig.PortBindings": {
                    "80/tcp": [{"HostIp": "", "HostPort": "8080"}],
                    "443/tcp": [{"HostIp": "127.0.0.1", "HostPort": "8443"}],
                    "3306/tcp": [{"HostIp": "0.0.0.0", "HostPort": ""}],  # 随机端口
                }
            }
        )
        attrs["Config"]["ExposedPorts"] = {"80/tcp": {}, "443/tcp": {}, "3306/tcp": {}}
        params = build_create_params(attrs)

        assert params["ports"]["80/tcp"] == ("", "8080")
        assert params["ports"]["443/tcp"] == ("127.0.0.1", "8443")
        assert params["ports"]["3306/tcp"] == ("0.0.0.0", None)

    def test_exposed_only_port_maps_to_none(self):
        """只声明未绑定的端口（ExposedPorts 有、PortBindings 无）→ None。"""
        attrs = make_attrs()
        attrs["Config"]["ExposedPorts"] = {"8080/tcp": {}}
        attrs["HostConfig"]["PortBindings"] = {}
        params = build_create_params(attrs)
        assert params["ports"] == {"8080/tcp": None}

    def test_no_exposed_ports(self):
        """无暴露端口时 ports 为空 dict。"""
        attrs = make_attrs()
        attrs["Config"]["ExposedPorts"] = None
        attrs["HostConfig"]["PortBindings"] = {}
        params = build_create_params(attrs)
        assert params["ports"] == {}

    def test_custom_network_with_aliases_and_static_ip(self):
        """自定义网络应保留网络名、别名与固定 IP。"""
        params = build_create_params(make_attrs())
        assert params["networks"] == {
            "mp_1_default": {
                "aliases": ["web"],
                "ipam": {"IPv4Address": "172.20.0.5"},
            }
        }
        assert "network_mode" not in params

    def test_host_network_mode(self):
        """host 网络模式直接透传。"""
        attrs = make_attrs(
            **{
                "HostConfig.NetworkMode": "host",
                "NetworkSettings.Networks": {"host": {}},
            }
        )
        params = build_create_params(attrs)
        assert params["network_mode"] == "host"
        assert "networks" not in params

    def test_bridge_network_mode(self):
        """bridge 网络模式直接透传，无需 networks 参数。"""
        attrs = make_attrs(
            **{
                "HostConfig.NetworkMode": "bridge",
                "NetworkSettings.Networks": {"bridge": {}},
            }
        )
        params = build_create_params(attrs)
        assert params["network_mode"] == "bridge"
        assert "networks" not in params

    def test_container_network_mode_rejected(self):
        """container:xxx 网络模式依赖原容器，升级后失效，应拒绝。"""
        attrs = make_attrs(**{"HostConfig.NetworkMode": "container:abc123"})
        with pytest.raises(ValueError, match="container"):
            build_create_params(attrs)

    def test_multiple_networks_all_preserved(self):
        """容器连接多个自定义网络时全部保留（含别名/IP）。"""
        attrs = make_attrs(
            **{
                "HostConfig.NetworkMode": "net1",
                "NetworkSettings.Networks": {
                    "net1": {"Aliases": ["web"], "IPAMConfig": {"IPv4Address": "172.20.0.5"}},
                    "net2": {"Aliases": ["extra"]},
                },
            }
        )
        params = build_create_params(attrs)
        assert params["networks"] == {
            "net1": {"aliases": ["web"], "ipam": {"IPv4Address": "172.20.0.5"}},
            "net2": {"aliases": ["extra"]},
        }

    def test_healthcheck_converted_to_seconds(self):
        """healthcheck 的纳秒间隔/超时应转换为秒。"""
        params = build_create_params(make_attrs())
        assert params["healthcheck"] == {
            "test": ["CMD-SHELL", "curl -f http://localhost/ || exit 1"],
            "interval": 30,
            "timeout": 3,
            "retries": 3,
            "start_period": 5,
        }

    def test_missing_config_sections_are_tolerated(self):
        """attrs 缺省字段（如无 Healthcheck/Devices/Env）不应报错。"""
        attrs = make_attrs()
        attrs["Config"].pop("Healthcheck", None)
        attrs["Config"].pop("Env", None)
        attrs["Config"].pop("Labels", None)
        attrs["HostConfig"].pop("Devices", None)
        attrs["HostConfig"].pop("PortBindings", None)
        attrs["Config"]["ExposedPorts"] = None
        params = build_create_params(attrs)
        assert params["environment"] == {}
        assert "healthcheck" not in params
        assert params["labels"] == {}
        assert params["devices"] == []
        assert params["ports"] == {}


# ---------- check_container_update ----------

class TestCheckContainerUpdate:
    def test_returns_update_available_when_digest_differs(self):
        """pull 后最新镜像 Id 与容器 ImageID 不同 → 有更新。"""
        container = make_container()
        client = make_client(container, latest_image_id="sha256:new-digest-222")
        result = check_container_update(client, "abc123")

        assert result["status"] == "update_available"
        assert result["current_image"] == "nginx:1.25"
        assert result["current_digest"] == "sha256:old-digest-111"
        assert result["latest_digest"] == "sha256:new-digest-222"
        client.images.pull.assert_called_once_with("nginx", tag="1.25")

    def test_up_to_date_when_digest_same(self):
        """pull 后镜像 Id 与容器 ImageID 相同 → 已是最新。"""
        container = make_container()
        client = make_client(container, latest_image_id="sha256:old-digest-111")
        result = check_container_update(client, "abc123")
        assert result["status"] == "up_to_date"

    def test_falls_back_to_repodigests_without_imageid(self):
        """无 ImageID 时回退用 RepoDigests 对比。"""
        container = make_container()
        attrs = container.attrs
        attrs["ImageID"] = None
        attrs["RepoDigests"] = ["nginx@sha256:repo-old"]
        client = make_client(container)
        client.images.get.return_value = MagicMock(
            attrs={"Id": "x", "RepoDigests": ["nginx@sha256:repo-new"]}
        )
        result = check_container_update(client, "abc123")
        assert result["status"] == "update_available"

    def test_unknown_without_any_digest_info(self):
        """容器与最新镜像均无 digest 信息（如本地构建镜像）→ unknown。"""
        container = make_container()
        attrs = container.attrs
        attrs["ImageID"] = None
        attrs["RepoDigests"] = []
        client = make_client(container)
        client.images.get.return_value = MagicMock(attrs={"Id": "x", "RepoDigests": []})
        result = check_container_update(client, "abc123")
        assert result["status"] == "unknown"

    def test_no_tag_defaults_to_latest(self):
        """无 tag 的镜像引用默认拉取 latest。"""
        container = make_container()
        container.attrs["Config"]["Image"] = "nginx"
        client = make_client(container)
        check_container_update(client, "abc123")
        client.images.pull.assert_called_once_with("nginx", tag="latest")

    def test_container_not_found_raises(self):
        """容器不存在时抛 NotFound。"""
        client = MagicMock()
        client.containers.get.side_effect = Exception("not found")
        with pytest.raises(Exception):
            check_container_update(client, "nope")

    def test_pull_failure_propagates(self):
        """pull 失败（如远端无此 tag）应抛出异常，由 API 层转 500。"""
        container = make_container()
        client = make_client(container)
        client.images.pull.side_effect = Exception("pull failed: not found")
        with pytest.raises(Exception, match="pull failed"):
            check_container_update(client, "abc123")


# ---------- upgrade_container ----------

class TestUpgradeContainer:
    def test_upgrade_flow_with_same_name(self):
        """升级流程：临时名 create → stop → remove → rename 原名 → start。"""
        container = make_container()
        client = make_client(container, latest_image_id="sha256:new-digest-222")
        new_container = MagicMock()
        new_container.id = "sha256:new-id"
        new_container.short_id = "new-id"
        new_container.name = "my-nginx-upgrading-12345678"
        client.containers.create.return_value = new_container

        result = upgrade_container(client, "abc123")

        assert result["status"] == "upgraded"
        assert result["id"] == "sha256:new-id"
        assert result["name"] == "my-nginx"
        # 拉取最新镜像
        client.images.pull.assert_called_once()
        # 创建参数包含保留的配置（端口/挂载/环境变量）
        create_kwargs = client.containers.create.call_args[1]
        assert create_kwargs["image"] == "nginx:1.25"
        # 临时名 = 原名 + upgrading 后缀（含随机段）
        assert create_kwargs["name"].startswith("my-nginx-upgrading-")
        assert create_kwargs["name"] != "my-nginx"
        assert create_kwargs["environment"] == {"NGINX_PORT": "80", "DEBUG": "true"}
        assert create_kwargs["binds"] == ["/data:/data:ro", "vol1:/etc/vol1"]
        assert create_kwargs["ports"]["80/tcp"] == ("", "8080")
        # 旧容器 stop + remove（保留卷 v=False），新容器 rename + start
        container.stop.assert_called_once()
        container.remove.assert_called_once_with(force=True, v=False)
        new_container.rename.assert_called_once_with("my-nginx")
        new_container.start.assert_called_once()

    def test_up_to_date_skips_recreate(self):
        """已是最新版本时直接返回，不重建容器。"""
        container = make_container()
        client = make_client(container, latest_image_id="sha256:old-digest-111")
        result = upgrade_container(client, "abc123")
        assert result["status"] == "up_to_date"
        client.containers.create.assert_not_called()
        container.remove.assert_not_called()

    def test_stopped_container_skips_stop(self):
        """旧容器已停止时跳过 stop，直接 remove。"""
        container = make_container(status="exited")
        client = make_client(container, latest_image_id="sha256:new-digest-222")
        new_container = MagicMock()
        new_container.id = "sha256:new-id"
        new_container.name = "my-nginx-upgrading-12345678"
        client.containers.create.return_value = new_container
        upgrade_container(client, "abc123")
        container.stop.assert_not_called()
        container.remove.assert_called_once_with(force=True, v=False)
        new_container.start.assert_called_once()

    def test_create_failure_keeps_old_container(self):
        """新容器创建失败时旧容器必须原样保留（不 stop 不 remove）。"""
        container = make_container()
        client = make_client(container, latest_image_id="sha256:new-digest-222")
        client.containers.create.side_effect = Exception("image pull error")
        with pytest.raises(Exception, match="image pull error"):
            upgrade_container(client, "abc123")
        container.stop.assert_not_called()
        container.remove.assert_not_called()

    def test_container_mode_network_rejected_before_any_change(self):
        """container: 网络模式的容器拒绝升级，且不执行任何变更。"""
        container = make_container()
        container.attrs["HostConfig"]["NetworkMode"] = "container:other123"
        client = make_client(container, latest_image_id="sha256:new-digest-222")
        with pytest.raises(ValueError, match="container"):
            upgrade_container(client, "abc123")
        container.remove.assert_not_called()
        client.containers.create.assert_not_called()


# ---------- API 层 ----------

class TestUpgradeApi:
    """POST /containers/{id}/check-update 与 /upgrade 接口层测试。"""

    def _headers(self, db_session):
        key_str = uuid.uuid4().hex
        db_session.add(APIKeyModel(key=key_str, note="测试"))
        db_session.commit()
        return {"X-API-Key": key_str}

    def test_check_update_endpoint(self, client, db_session):
        """check-update 接口返回 200 与结构化结果。"""
        container = make_container()
        mock_client = make_client(container, latest_image_id="sha256:new-digest-222")
        with patch(
            "app.routers.containers.get_docker_client", return_value=mock_client
        ):
            response = client.post(
                "/containers/abc123/check-update", headers=self._headers(db_session)
            )
        assert response.status_code == 200
        body = response.json()
        assert body["status"] == "update_available"
        assert body["current_image"] == "nginx:1.25"
        assert body["latest_digest"] == "sha256:new-digest-222"

    def test_upgrade_endpoint(self, client, db_session):
        """upgrade 接口返回 200 与新容器信息。"""
        container = make_container()
        mock_client = make_client(container, latest_image_id="sha256:new-digest-222")
        new_container = MagicMock()
        new_container.id = "sha256:new-id"
        new_container.short_id = "new-id"
        new_container.name = "my-nginx"
        mock_client.containers.create.return_value = new_container
        with patch(
            "app.routers.containers.get_docker_client", return_value=mock_client
        ):
            response = client.post(
                "/containers/abc123/upgrade", headers=self._headers(db_session)
            )
        assert response.status_code == 200
        body = response.json()
        assert body["status"] == "upgraded"
        assert body["name"] == "my-nginx"

    def test_upgrade_endpoint_error_returns_500(self, client, db_session):
        """upgrade 失败（如 pull 异常）时返回 500 与错误信息。"""
        container = make_container()
        mock_client = make_client(container, latest_image_id="sha256:new-digest-222")
        mock_client.images.pull.side_effect = Exception("network unreachable")
        with patch(
            "app.routers.containers.get_docker_client", return_value=mock_client
        ):
            response = client.post(
                "/containers/abc123/upgrade", headers=self._headers(db_session)
            )
        assert response.status_code == 500
        assert "network unreachable" in response.json()["detail"]

    def test_check_update_requires_api_key(self, client, db_session):
        """未带 API key 时返回 401。"""
        response = client.post("/containers/abc123/check-update")
        assert response.status_code == 401
