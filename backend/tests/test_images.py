"""镜像列表 API 集成测试。"""

import uuid
from unittest.mock import MagicMock, patch

from app.db.models import APIKeyModel


def _make_image(image_id, tags):
    """构造一个模拟的 docker Image 对象。"""
    img = MagicMock()
    img.id = image_id
    img.tags = tags
    img.short_id = image_id[:12]
    img.attrs = {"Created": "2024-01-01T00:00:00Z", "Size": 100}
    img.labels = {}
    return img


def _make_container(image_id):
    container = MagicMock()
    container.attrs = {"Image": image_id}
    return container


class TestListImages:
    def test_list_images_excludes_dangling_images(self, client, db_session):
        """列表应排除 RepoTags 为 <none>:<none> 的悬空镜像和无 tag 镜像。"""
        key_str = uuid.uuid4().hex
        db_session.add(APIKeyModel(key=key_str, note="测试"))
        db_session.commit()

        nginx = _make_image("sha256:1111", ["nginx:latest"])
        dangling = _make_image("sha256:2222", ["<none>:<none>"])
        untagged = _make_image("sha256:3333", [])
        # 悬空镜像即使被容器使用也应与群晖 Container Manager 一致地隐藏
        in_use_dangling = _make_image("sha256:4444", ["<none>:<none>"])

        mock_client = MagicMock()
        mock_client.images.list.return_value = [nginx, dangling, untagged, in_use_dangling]
        mock_client.containers.list.return_value = [_make_container("sha256:4444")]

        with patch("app.routers.images.get_docker_client", return_value=mock_client):
            response = client.get("/images", headers={"X-API-Key": key_str})

        assert response.status_code == 200
        result = response.json()
        # 只有 nginx 有有效 tag，应保留
        assert len(result) == 1
        assert result[0]["tags"] == ["nginx:latest"]

    def test_list_images_keeps_multi_tagged_images(self, client, db_session):
        """多 tag 镜像只要含一个有效 tag 就应保留。"""
        key_str = uuid.uuid4().hex
        db_session.add(APIKeyModel(key=key_str, note="测试"))
        db_session.commit()

        multi = _make_image("sha256:5555", ["myapp:1.0", "myapp:latest"])

        mock_client = MagicMock()
        mock_client.images.list.return_value = [multi]
        mock_client.containers.list.return_value = []

        with patch("app.routers.images.get_docker_client", return_value=mock_client):
            response = client.get("/images", headers={"X-API-Key": key_str})

        assert response.status_code == 200
        result = response.json()
        assert len(result) == 1
        assert result[0]["tags"] == ["myapp:1.0", "myapp:latest"]
