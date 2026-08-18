from unittest.mock import MagicMock
from app.core.utils import process_container_summary


class TestProcessContainerSummary:
    def test_basic_container_summary(self):
        container = MagicMock()
        container.id = "abc123def456"
        container.name = "web-server"
        container.status = "running"
        container.labels = {}
        container.attrs = {
            "Image": "sha256:abc123",
            "Ports": [],
        }
        container.image.tags = ["nginx:latest"]

        result = process_container_summary(container)

        assert result["id"] == "abc123def456"
        assert result["name"] == "web-server"
        assert result["status"] == "running"
        assert result["stack"] == ""
        assert result["image"] == "nginx:latest"
        assert result["ports"] == ""
        assert result["is_self"] is False

    def test_ports_formatting(self):
        container = MagicMock()
        container.id = "test-id"
        container.name = "test"
        container.status = "running"
        container.labels = {}
        container.attrs = {
            "Image": "nginx:latest",
            "Ports": [
                {"PublicPort": 8080, "PrivatePort": 80, "Type": "tcp"},
                {"PublicPort": 8443, "PrivatePort": 443, "Type": "tcp"},
            ],
        }
        container.image.tags = ["nginx:latest"]

        result = process_container_summary(container)

        assert "8080->80/tcp" in result["ports"]
        assert "8443->443/tcp" in result["ports"]

    def test_stack_from_labels(self):
        container = MagicMock()
        container.id = "test-id"
        container.name = "test"
        container.status = "running"
        container.labels = {"com.docker.compose.project": "myapp"}
        container.attrs = {"Image": "alpine", "Ports": []}
        container.image.tags = ["alpine:latest"]

        result = process_container_summary(container)

        assert result["stack"] == "myapp"

    def test_sha256_image_resolved(self):
        container = MagicMock()
        container.id = "test-id"
        container.name = "test"
        container.status = "running"
        container.labels = {}
        container.attrs = {"Image": "sha256:deadbeef", "Ports": []}
        container.image.tags = ["myimage:v1.0"]

        result = process_container_summary(container)

        assert result["image"] == "myimage:v1.0"

    def test_is_self_by_full_id(self):
        container = MagicMock()
        container.id = "abc123def456789"
        container.name = "test"
        container.status = "running"
        container.labels = {}
        container.attrs = {"Image": "alpine", "Ports": []}
        container.image.tags = ["alpine:latest"]

        result = process_container_summary(container, self_id="abc123def456789")

        assert result["is_self"] is True

    def test_is_self_by_short_id(self):
        container = MagicMock()
        container.id = "abc123def456789"
        container.name = "test"
        container.status = "running"
        container.labels = {}
        container.attrs = {"Image": "alpine", "Ports": []}
        container.image.tags = ["alpine:latest"]

        result = process_container_summary(container, self_id="abc123")

        assert result["is_self"] is True

    def test_exposed_ports_without_mapping(self):
        """仅暴露未映射的端口（Config.ExposedPorts）也应出现在摘要中（issue #48）。"""
        container = MagicMock()
        container.id = "test-id"
        container.name = "test"
        container.status = "running"
        container.labels = {}
        container.attrs = {
            "Image": "nginx:latest",
            "Ports": [],
            "Config": {"ExposedPorts": {"80/tcp": {}, "443/tcp": {}}},
        }
        container.image.tags = ["nginx:latest"]

        result = process_container_summary(container)

        assert "80/tcp" in result["ports"]
        assert "443/tcp" in result["ports"]
        # ports_list 中未映射条目 public_port 为 None
        exposed = [p for p in result["ports_list"] if p["public_port"] is None]
        assert len(exposed) == 2
        assert {"public_port": None, "private_port": 80, "type": "tcp"} in exposed
        assert {"public_port": None, "private_port": 443, "type": "tcp"} in exposed

    def test_exposed_and_published_ports_merged(self):
        """已映射端口与仅暴露端口合并展示，映射关系格式保持 x->y/z（issue #48）。"""
        container = MagicMock()
        container.id = "test-id"
        container.name = "test"
        container.status = "running"
        container.labels = {}
        container.attrs = {
            "Image": "nginx:latest",
            "Ports": [
                {"PublicPort": 8080, "PrivatePort": 80, "Type": "tcp"},
            ],
            "Config": {"ExposedPorts": {"80/tcp": {}, "443/tcp": {}}},
        }
        container.image.tags = ["nginx:latest"]

        result = process_container_summary(container)

        # 已映射端口保持 x->y/z 格式
        assert "8080->80/tcp" in result["ports"]
        # 未映射暴露端口以 端口/协议 格式补充
        assert "443/tcp" in result["ports"]
        # 端口 80 同时有映射与暴露声明，不应重复出现未映射条目
        exposed = [p for p in result["ports_list"] if p["public_port"] is None]
        assert len(exposed) == 1
        assert exposed[0] == {"public_port": None, "private_port": 443, "type": "tcp"}
