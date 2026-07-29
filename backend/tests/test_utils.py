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
