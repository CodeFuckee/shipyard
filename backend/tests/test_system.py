"""系统信息 API 集成测试。"""

import uuid
from unittest.mock import MagicMock, patch

from app.db.models import APIKeyModel


def _make_image(image_id, tags):
    """构造一个模拟的 docker Image 对象。"""
    img = MagicMock()
    img.id = image_id
    img.tags = tags
    img.attrs = {"Created": "2024-01-01T00:00:00Z", "Size": 100}
    img.labels = {}
    img.status = "running"
    return img


class TestSystemInfoImageCount:
    def test_image_count_excludes_dangling_images(self, client, db_session):
        """概览信息中的镜像数量应排除悬空镜像（<none>:<none>）。"""
        key_str = uuid.uuid4().hex
        db_session.add(APIKeyModel(key=key_str, note="测试"))
        db_session.commit()

        nginx = _make_image("sha256:1111", ["nginx:latest"])
        redis = _make_image("sha256:2222", ["redis:7.0"])
        myapp = _make_image("sha256:3333", ["myapp:1.0", "myapp:latest"])
        dangling = _make_image("sha256:4444", ["<none>:<none>"])
        untagged = _make_image("sha256:5555", [])

        mock_client = MagicMock()
        mock_client.images.list.return_value = [nginx, redis, myapp, dangling, untagged]
        mock_client.containers.list.return_value = []

        with patch("app.routers.system.get_docker_client", return_value=mock_client):
            response = client.get("/info", headers={"X-API-Key": key_str})

        assert response.status_code == 200
        docker_stats = response.json()["docker"]
        # 5 个镜像中只有 3 个有有效 tag
        assert docker_stats["images"] == 3
