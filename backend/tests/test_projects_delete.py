"""DELETE /projects/{id} 删除项目功能测试。

覆盖：
1. 正常路径：删除数据库记录 + 删除服务器上项目文件夹
2. 边界：404（项目不存在）、409（构建中不可删）
3. 资源清理：有 compose 文件时执行 docker compose down，无文件时跳过
4. 容错：文件夹缺失、compose down 失败时删除仍成功（尽力而为）
5. 删除后列表不再包含该项目
"""

import pathlib
import uuid
from unittest.mock import patch

import pytest

from app.db.models import APIKeyModel, ProjectModel
from tests.conftest import TestSessionLocal


@pytest.fixture(autouse=True)
def _tmp_projects_dir(monkeypatch, tmp_path):
    """将 PROJECTS_DIR 指向临时目录，避免污染真实 data/projects。"""
    d = tmp_path / "projects"
    monkeypatch.setattr("app.core.config.PROJECTS_DIR", str(d))
    monkeypatch.setattr("app.routers.projects.PROJECTS_DIR", str(d))
    monkeypatch.setattr("app.mcp.tools.PROJECTS_DIR", str(d))
    return d


def _auth_headers(db_session) -> dict:
    """创建 API Key 并返回认证头。"""
    key_str = uuid.uuid4().hex
    db_session.add(APIKeyModel(key=key_str, note="测试"))
    db_session.commit()
    return {"X-API-Key": key_str}


def _create_project(client, db_session, name: str = "app1") -> dict:
    """通过 POST /projects 创建项目（不带 git_url，生成默认模板），返回响应数据。"""
    headers = _auth_headers(db_session)
    resp = client.post("/projects", json={"name": name}, headers=headers)
    assert resp.status_code == 201
    return resp.json()


def _project_dir(projects_dir, project_id: str) -> pathlib.Path:
    return pathlib.Path(projects_dir) / project_id


class TestDeleteProjectSuccess:
    """正常路径。"""

    def test_delete_removes_db_record_and_folder(
        self, client, db_session, _tmp_projects_dir
    ):
        """删除项目后：返回 deleted、数据库无记录、服务器文件夹被删除。"""
        data = _create_project(client, db_session)
        headers = _auth_headers(db_session)
        project_id = data["id"]
        folder = _project_dir(_tmp_projects_dir, project_id)
        assert folder.exists()

        resp = client.delete(f"/projects/{project_id}", headers=headers)

        assert resp.status_code == 200
        assert resp.json()["status"] == "deleted"
        # 数据库记录已删除
        assert (
            db_session.query(ProjectModel)
            .filter(ProjectModel.id == project_id)
            .first()
            is None
        )
        # 文件夹已删除
        assert not folder.exists()

    def test_delete_without_git_url_folder_removed(
        self, client, db_session, _tmp_projects_dir
    ):
        """普通模板项目删除后文件夹（含 Dockerfile/compose 文件）一并清除。"""
        data = _create_project(client, db_session, name="plain")
        headers = _auth_headers(db_session)
        folder = _project_dir(_tmp_projects_dir, data["id"])
        assert (folder / "Dockerfile").exists()

        resp = client.delete(f"/projects/{data['id']}", headers=headers)

        assert resp.status_code == 200
        assert not folder.exists()

    def test_deleted_project_not_in_list(self, client, db_session, _tmp_projects_dir):
        """删除后 GET /projects 列表不再包含该项目。"""
        data = _create_project(client, db_session)
        headers = _auth_headers(db_session)

        client.delete(f"/projects/{data['id']}", headers=headers)
        resp = client.get("/projects", headers=headers)

        assert resp.status_code == 200
        ids = [p["id"] for p in resp.json()]
        assert data["id"] not in ids

    def test_delete_removed_project_returns_404_on_get(
        self, client, db_session, _tmp_projects_dir
    ):
        """删除后再次 GET 项目详情返回 404。"""
        data = _create_project(client, db_session)
        headers = _auth_headers(db_session)

        client.delete(f"/projects/{data['id']}", headers=headers)
        resp = client.get(f"/projects/{data['id']}", headers=headers)

        assert resp.status_code == 404


class TestDeleteProjectComposeCleanup:
    """删除时对运行中容器的清理（docker compose down）。"""

    def test_delete_runs_compose_down_when_compose_exists(
        self, client, db_session, _tmp_projects_dir
    ):
        """存在 docker-compose.yaml 时应执行 docker compose down --volumes。"""
        data = _create_project(client, db_session)
        headers = _auth_headers(db_session)
        project_id = data["id"]
        assert (
            _project_dir(_tmp_projects_dir, project_id) / "docker-compose.yaml"
        ).exists()

        with patch("app.routers.projects.subprocess.run") as mock_run:
            resp = client.delete(f"/projects/{project_id}", headers=headers)

        assert resp.status_code == 200
        mock_run.assert_called_once()
        cmd = mock_run.call_args.args[0]
        assert cmd[0] == "docker"
        assert cmd[1] == "compose"
        assert cmd[3] == str(_project_dir(_tmp_projects_dir, project_id) / "docker-compose.yaml")
        assert cmd[5] == f"mp_{project_id}"
        assert cmd[6] == "down"
        assert cmd[7] == "--volumes"

    def test_delete_skips_compose_down_without_compose_file(
        self, client, db_session, _tmp_projects_dir
    ):
        """项目文件夹没有 docker-compose.yaml 时不应调用 docker compose。"""
        # 直接向数据库插入记录并建空文件夹，模拟没有 compose 文件的旧项目
        headers = _auth_headers(db_session)
        project_id = f"proj_{uuid.uuid4().hex[:12]}"
        folder = _project_dir(_tmp_projects_dir, project_id)
        folder.mkdir(parents=True)
        (folder / "Dockerfile").write_text("FROM alpine\n", encoding="utf-8")
        db_session.add(
            ProjectModel(
                id=project_id,
                name="nocompose",
                status="idle",
            )
        )
        db_session.commit()

        with patch("app.routers.projects.subprocess.run") as mock_run:
            resp = client.delete(f"/projects/{project_id}", headers=headers)

        assert resp.status_code == 200
        mock_run.assert_not_called()
        assert not folder.exists()


class TestDeleteProjectErrors:
    """异常与边界。"""

    def test_delete_not_found_404(self, client, db_session):
        """删除不存在的项目返回 404。"""
        headers = _auth_headers(db_session)
        resp = client.delete(f"/projects/proj_nonexistent_{uuid.uuid4().hex[:8]}", headers=headers)
        assert resp.status_code == 404

    def test_delete_while_building_conflict(self, client, db_session, _tmp_projects_dir):
        """项目正在构建时返回 409，记录与文件夹均保留。"""
        data = _create_project(client, db_session)
        headers = _auth_headers(db_session)
        project_id = data["id"]

        # 将项目状态改为 building
        project = (
            db_session.query(ProjectModel)
            .filter(ProjectModel.id == project_id)
            .first()
        )
        project.status = "building"
        db_session.commit()

        resp = client.delete(f"/projects/{project_id}", headers=headers)

        assert resp.status_code == 409
        # 记录与文件夹均未被删除
        assert (
            db_session.query(ProjectModel)
            .filter(ProjectModel.id == project_id)
            .first()
            is not None
        )
        assert _project_dir(_tmp_projects_dir, project_id).exists()

    def test_delete_tolerates_missing_folder(self, client, db_session, _tmp_projects_dir):
        """数据库有记录但文件夹已不存在时删除仍成功（尽力而为）。"""
        headers = _auth_headers(db_session)
        project_id = f"proj_{uuid.uuid4().hex[:12]}"
        db_session.add(
            ProjectModel(
                id=project_id,
                name="ghost",
                status="idle",
            )
        )
        db_session.commit()

        resp = client.delete(f"/projects/{project_id}", headers=headers)

        assert resp.status_code == 200
        assert resp.json()["status"] == "deleted"

    def test_delete_tolerates_compose_down_failure(
        self, client, db_session, _tmp_projects_dir
    ):
        """docker compose down 失败/超时不应阻止删除（尽力而为）。"""
        data = _create_project(client, db_session)
        headers = _auth_headers(db_session)

        with patch(
            "app.routers.projects.subprocess.run",
            side_effect=Exception("docker daemon unreachable"),
        ):
            resp = client.delete(f"/projects/{data['id']}", headers=headers)

        assert resp.status_code == 200
        assert resp.json()["status"] == "deleted"

    def test_delete_requires_auth(self, client, db_session):
        """无 API Key 时删除被拒绝（401）。"""
        resp = client.delete("/projects/proj_whatever")
        assert resp.status_code == 401
