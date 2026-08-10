"""POST /projects 的 gitUrl（git clone 创建项目）功能测试。

覆盖三部分：
1. 公共模块 app.core.git_clone 的单元测试（URL 校验/仓库名提取/凭据注入/脱敏）
2. REST POST /projects 的 gitUrl 参数集成测试（正常路径 + 异常回滚）
3. MCP create_project 工具的 git_url 参数测试

git clone 不依赖真实网络：所有 clone 操作通过 mock 模拟。
"""

import pathlib
import uuid
from unittest.mock import patch

import pytest

from app.core import git_clone
from app.db.models import APIKeyModel, ProjectModel
from tests.conftest import TestSessionLocal

# ---------------------------------------------------------------------------
# fixtures 与辅助
# ---------------------------------------------------------------------------


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


def _fake_clone(*files: str):
    """构造模拟 git clone 成功的 side_effect：在 dest 目录写入指定文件并创建 .git。"""

    def _clone(url, dest, timeout=120):
        dest = pathlib.Path(dest)
        dest.mkdir(parents=True, exist_ok=True)
        (dest / ".git").mkdir(exist_ok=True)
        for f in files:
            p = dest / f
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(f"# cloned from {url}\n", encoding="utf-8")

    return _clone


class _FakeServer:
    """模拟 MCPServer，仅收集 @server.tool 注册的原始函数（与 test_mcp_tools.py 一致）。"""

    def __init__(self):
        self._tools = {}

    def tool(self, **kwargs):
        def decorator(fn):
            self._tools[fn.__name__] = fn
            return fn

        return decorator


@pytest.fixture
def mcp_tools():
    """注册全部 MCP 工具，返回 {函数名: 原始函数}，并将 DB 会话指向测试库。"""
    import app.mcp.tools as tools_module

    fake = _FakeServer()
    tools_module.register_all_tools(fake)

    # MCP 工具的 get_db_session 走真实 SessionLocal，必须指向测试库；
    # patch 必须在整个测试期间生效，因此用 with + yield fixture
    with patch.object(tools_module, "get_db_session", side_effect=_test_db_session):
        yield fake._tools


def _test_db_session():
    """测试用 get_db_session 上下文管理器（使用 conftest 的 TestSessionLocal）。"""
    from contextlib import contextmanager

    @contextmanager
    def _session():
        db = TestSessionLocal()
        try:
            yield db
        finally:
            db.close()

    return _session()


# ---------------------------------------------------------------------------
# 公共模块单元测试
# ---------------------------------------------------------------------------


class TestExtractRepoName:
    """从 git URL 提取仓库名。"""

    @pytest.mark.parametrize(
        "url,expected",
        [
            ("https://example.com/user/myapp.git", "myapp"),
            ("https://example.com/user/myapp", "myapp"),
            ("https://example.com/user/myapp/", "myapp"),
            ("https://example.com:8443/user/tool.git", "tool"),
            ("https://user:pass@example.com/org/repo.git", "repo"),
            ("git@github.com:user/app.git", "app"),
            ("git@github.com:user/app", "app"),
            ("http://example.com/a/b/c", "c"),
        ],
    )
    def test_extract_repo_name(self, url, expected):
        assert git_clone.extract_repo_name(url) == expected

    @pytest.mark.parametrize(
        "url",
        [
            "",
            "   ",
            "https://example.com/",
            "https://example.com/.",
            "git@example.com:",
            "git@example.com",
            "not-a-url",
            "ftp://example.com/repo.git",
        ],
    )
    def test_extract_repo_name_invalid(self, url):
        with pytest.raises(ValueError):
            git_clone.extract_repo_name(url)


class TestValidateGitUrl:
    """URL 格式校验。"""

    @pytest.mark.parametrize(
        "url",
        [
            "https://example.com/user/repo.git",
            "http://example.com/user/repo",
            "git@github.com:user/repo.git",
        ],
    )
    def test_valid_urls_accepted(self, url):
        # 不应抛异常
        git_clone.normalize_git_url(url)

    @pytest.mark.parametrize(
        "url",
        [
            "",
            "   ",
            "ftp://example.com/repo.git",
            "file:///etc/passwd",
            "javascript:alert(1)",
            "not-a-url",
            "--upload-pack=echo hacked",  # git 参数注入防护：不允许以 - 开头
            "-c core.sshCommand=evil",
            "git@github.com",  # SSH 格式缺少路径
            "git@example.com:/abs/path",  # SSH 路径不允许绝对路径
        ],
    )
    def test_invalid_urls_rejected(self, url):
        with pytest.raises(ValueError):
            git_clone.normalize_git_url(url)


class TestCredentialInjection:
    """环境变量默认凭据注入。"""

    def test_env_credentials_injected_into_http_url(self, monkeypatch):
        monkeypatch.setenv("GIT_USERNAME", "bot")
        monkeypatch.setenv("GIT_PASSWORD", "secret")
        result = git_clone.normalize_git_url("https://example.com/user/repo.git")
        from urllib.parse import urlsplit

        parts = urlsplit(result)
        assert parts.username == "bot"
        assert parts.password == "secret"

    def test_env_credentials_not_injected_when_url_has_credentials(self, monkeypatch):
        monkeypatch.setenv("GIT_USERNAME", "bot")
        monkeypatch.setenv("GIT_PASSWORD", "secret")
        result = git_clone.normalize_git_url(
            "https://realuser:realpass@example.com/user/repo.git"
        )
        from urllib.parse import urlsplit

        parts = urlsplit(result)
        assert parts.username == "realuser"
        assert parts.password == "realpass"

    def test_env_credentials_not_injected_for_ssh_url(self, monkeypatch):
        monkeypatch.setenv("GIT_USERNAME", "bot")
        monkeypatch.setenv("GIT_PASSWORD", "secret")
        result = git_clone.normalize_git_url("git@github.com:user/repo.git")
        assert result == "git@github.com:user/repo.git"

    def test_no_env_credentials_url_unchanged(self, monkeypatch):
        monkeypatch.delenv("GIT_USERNAME", raising=False)
        monkeypatch.delenv("GIT_PASSWORD", raising=False)
        result = git_clone.normalize_git_url("https://example.com/user/repo.git")
        assert result == "https://example.com/user/repo.git"

    def test_special_chars_in_credentials_are_encoded(self, monkeypatch):
        monkeypatch.setenv("GIT_USERNAME", "user@example.com")
        monkeypatch.setenv("GIT_PASSWORD", "p@ss:word")
        result = git_clone.normalize_git_url("https://example.com/user/repo.git")
        # @ 和 : 在 userinfo 中必须被百分号编码，避免破坏 URL 结构
        assert "user%40example.com:p%40ss%3Aword@" in result

    def test_ssh_url_without_credentials_accepted(self, monkeypatch):
        monkeypatch.delenv("GIT_USERNAME", raising=False)
        result = git_clone.normalize_git_url("git@github.com:user/repo.git")
        assert result == "git@github.com:user/repo.git"


class TestSanitizeUrl:
    """URL 密码脱敏。"""

    def test_password_hidden(self):
        assert git_clone.sanitize_url("https://user:secret@example.com/repo.git") == (
            "https://user:***@example.com/repo.git"
        )

    def test_no_credentials_unchanged(self):
        url = "https://example.com/repo.git"
        assert git_clone.sanitize_url(url) == url

    def test_ssh_url_unchanged(self):
        url = "git@github.com:user/repo.git"
        assert git_clone.sanitize_url(url) == url

    def test_empty_password(self):
        assert git_clone.sanitize_url("https://user:@example.com/repo.git") == (
            "https://user:***@example.com/repo.git"
        )

    def test_plain_text_with_url_pattern(self):
        """异常消息中嵌入的带凭据 URL 也应被脱敏。"""
        msg = "Authentication failed for https://bot:secret@example.com/repo.git"
        assert "secret" not in git_clone.sanitize_url(msg)
        assert "bot:***@" in git_clone.sanitize_url(msg)


class TestCloneRepo:
    """clone_repo 的异常包装（GitPython 错误 → 脱敏的 RuntimeError）。"""

    def test_clone_timeout_wrapped_as_runtime_error(self):
        """GitPython 超时（GitCommandError）应被包装为 RuntimeError。"""
        from git.exc import GitCommandError

        with patch.object(
            git_clone.git.Repo,
            "clone_from",
            side_effect=GitCommandError("clone", "timed out"),
        ):
            with pytest.raises(RuntimeError, match="timed out"):
                git_clone.clone_repo(
                    "https://example.com/user/repo.git", pathlib.Path("/tmp/x")
                )

    def test_clone_error_message_does_not_leak_password(self):
        """GitCommandError 消息中的 URL 密码应被脱敏。"""
        from git.exc import GitCommandError

        err = GitCommandError(
            "clone",
            "fatal: Authentication failed for https://bot:secret@example.com/repo.git",
        )
        with patch.object(git_clone.git.Repo, "clone_from", side_effect=err):
            with pytest.raises(RuntimeError) as excinfo:
                git_clone.clone_repo(
                    "https://example.com/user/repo.git", pathlib.Path("/tmp/x")
                )

        assert "secret" not in str(excinfo.value)
        assert "bot:***@" in str(excinfo.value)

    def test_clone_success_calls_gitpython(self, tmp_path):
        """clone_repo 应通过 GitPython 克隆到目标目录。"""
        dest = tmp_path / "repo"
        with patch.object(git_clone.git.Repo, "clone_from") as mock_clone:
            git_clone.clone_repo("https://example.com/user/repo.git", dest)

        mock_clone.assert_called_once()
        # 保留 .git：GitPython 默认行为即保留，这里验证参数传递正确
        call_kwargs = mock_clone.call_args.kwargs
        assert call_kwargs["kill_after_timeout"] == 120


# ---------------------------------------------------------------------------
# REST POST /projects 集成测试
# ---------------------------------------------------------------------------


class TestRESTCreateProjectWithGitUrl:
    """正常路径。"""

    def test_create_with_git_url_uses_cloned_files(
        self, client, db_session, _tmp_projects_dir
    ):
        """提供 gitUrl 时应使用 clone 下来的仓库内容作为项目目录。"""
        headers = _auth_headers(db_session)
        payload = {"name": "myapp", "git_url": "https://example.com/user/myapp.git"}
        with patch(
            "app.routers.projects.clone_repo", side_effect=_fake_clone("Dockerfile")
        ):
            resp = client.post("/projects", json=payload, headers=headers)

        assert resp.status_code == 201
        data = resp.json()
        assert data["name"] == "myapp"

        project_dir = pathlib.Path(_tmp_projects_dir) / data["id"]
        assert (project_dir / ".git").is_dir()  # 保留 .git
        assert (project_dir / "Dockerfile").exists()
        assert "cloned from" in (project_dir / "Dockerfile").read_text(
            encoding="utf-8"
        )

    def test_create_with_git_url_name_defaults_to_repo_name(
        self, client, db_session
    ):
        """不传 name 时从 git URL 自动提取仓库名。"""
        headers = _auth_headers(db_session)
        payload = {"git_url": "https://example.com/user/myapp.git"}
        with patch(
            "app.routers.projects.clone_repo", side_effect=_fake_clone()
        ):
            resp = client.post("/projects", json=payload, headers=headers)

        assert resp.status_code == 201
        assert resp.json()["name"] == "myapp"

    def test_create_with_git_url_ssh_format(self, client, db_session):
        """SSH 格式 git@host:path 应被接受。"""
        headers = _auth_headers(db_session)
        payload = {"git_url": "git@github.com:user/tool.git"}
        with patch(
            "app.routers.projects.clone_repo", side_effect=_fake_clone()
        ) as mock_clone:
            resp = client.post("/projects", json=payload, headers=headers)

        assert resp.status_code == 201
        assert resp.json()["name"] == "tool"
        # SSH 格式不应注入环境凭据，clone 收到原 URL
        called_url = mock_clone.call_args.args[0]
        assert called_url == "git@github.com:user/tool.git"

    def test_create_with_git_url_repo_missing_dockerfile_gets_default_template(
        self, client, db_session, _tmp_projects_dir
    ):
        """clone 的仓库没有 Dockerfile 和 docker-compose.yaml 时自动补默认模板。"""
        headers = _auth_headers(db_session)
        payload = {"name": "emptyrepo", "git_url": "https://example.com/user/empty.git"}
        with patch(
            "app.routers.projects.clone_repo", side_effect=_fake_clone("README.md")
        ):
            resp = client.post("/projects", json=payload, headers=headers)

        assert resp.status_code == 201
        project_dir = pathlib.Path(_tmp_projects_dir) / resp.json()["id"]
        assert (project_dir / "README.md").exists()  # 仓库内容保留
        dockerfile = project_dir / "Dockerfile"
        assert dockerfile.exists()
        assert dockerfile.read_text(encoding="utf-8").startswith("FROM alpine:latest")
        compose = project_dir / "docker-compose.yaml"
        assert compose.exists()
        assert "services:" in compose.read_text(encoding="utf-8")

    def test_create_with_git_url_repo_partial_files_keep_repo_versions(
        self, client, db_session, _tmp_projects_dir
    ):
        """仓库已有 Dockerfile 时保留仓库版本，只补缺失的 docker-compose.yaml。"""
        headers = _auth_headers(db_session)
        payload = {"name": "partial", "git_url": "https://example.com/user/p.git"}
        with patch(
            "app.routers.projects.clone_repo", side_effect=_fake_clone("Dockerfile")
        ):
            resp = client.post("/projects", json=payload, headers=headers)

        assert resp.status_code == 201
        project_dir = pathlib.Path(_tmp_projects_dir) / resp.json()["id"]
        dockerfile = project_dir / "Dockerfile"
        assert "cloned from" in dockerfile.read_text(encoding="utf-8")  # 仓库版本保留
        compose = project_dir / "docker-compose.yaml"
        assert compose.exists()
        assert "services:" in compose.read_text(encoding="utf-8")

    def test_create_without_git_url_still_generates_default_templates(
        self, client, db_session, _tmp_projects_dir
    ):
        """回归：不传 gitUrl 时行为与之前一致（生成默认模板，不调用 clone）。"""
        headers = _auth_headers(db_session)
        payload = {"name": "plain"}
        with patch(
            "app.routers.projects.clone_repo", side_effect=_fake_clone()
        ) as mock_clone:
            resp = client.post("/projects", json=payload, headers=headers)

        assert resp.status_code == 201
        mock_clone.assert_not_called()
        project_dir = pathlib.Path(_tmp_projects_dir) / resp.json()["id"]
        assert (project_dir / "Dockerfile").exists()
        assert (project_dir / "docker-compose.yaml").exists()


class TestRESTCreateProjectWithGitUrlErrors:
    """异常与边界。"""

    def test_create_without_name_and_git_url_rejected(self, client, db_session):
        """name 和 gitUrl 都缺省时拒绝创建。"""
        headers = _auth_headers(db_session)
        resp = client.post("/projects", json={}, headers=headers)
        assert resp.status_code == 400

    def test_create_with_blank_name_and_no_git_url_rejected(
        self, client, db_session
    ):
        headers = _auth_headers(db_session)
        resp = client.post(
            "/projects", json={"name": "   "}, headers=headers
        )
        assert resp.status_code == 400

    @pytest.mark.parametrize(
        "git_url",
        [
            "ftp://example.com/repo.git",
            "not-a-url",
            "--upload-pack=echo hacked",
            "git@example.com",
        ],
    )
    def test_create_with_invalid_git_url_rejected(
        self, client, db_session, _tmp_projects_dir, git_url
    ):
        """非法 git URL 返回 400，且无项目记录和目录残留。"""
        headers = _auth_headers(db_session)
        payload = {"name": "bad", "git_url": git_url}
        with patch(
            "app.routers.projects.clone_repo", side_effect=_fake_clone()
        ) as mock_clone:
            resp = client.post("/projects", json=payload, headers=headers)

        assert resp.status_code == 400
        mock_clone.assert_not_called()  # 非法 URL 不应执行 clone
        assert db_session.query(ProjectModel).count() == 0
        assert not list(pathlib.Path(_tmp_projects_dir).glob("*"))

    def test_create_with_git_url_duplicate_name_rejected(
        self, client, db_session, _tmp_projects_dir
    ):
        """提取的仓库名与已有项目重名时拒绝创建。"""
        headers = _auth_headers(db_session)
        # 先创建一个同名项目
        with patch(
            "app.routers.projects.clone_repo", side_effect=_fake_clone()
        ):
            resp1 = client.post(
                "/projects", json={"name": "myapp"}, headers=headers
            )
            assert resp1.status_code == 201

        # 再通过 gitUrl 创建，仓库名同样是 myapp
        payload = {"git_url": "https://example.com/user/myapp.git"}
        with patch(
            "app.routers.projects.clone_repo", side_effect=_fake_clone()
        ) as mock_clone:
            resp2 = client.post("/projects", json=payload, headers=headers)

        assert resp2.status_code == 400
        assert "已存在" in resp2.json()["detail"]
        mock_clone.assert_not_called()

    def test_create_with_git_url_clone_failure_rolls_back(
        self, client, db_session, _tmp_projects_dir
    ):
        """clone 失败返回 400，项目记录和目录都回滚删除。"""
        headers = _auth_headers(db_session)
        payload = {"name": "myapp", "git_url": "https://example.com/user/myapp.git"}
        with patch(
            "app.routers.projects.clone_repo",
            side_effect=RuntimeError("Repository not found"),
        ):
            resp = client.post("/projects", json=payload, headers=headers)

        assert resp.status_code == 400
        assert "Repository not found" in resp.json()["detail"]
        # 回滚：无项目记录
        assert db_session.query(ProjectModel).count() == 0
        # 回滚：目录已删除
        assert not list(pathlib.Path(_tmp_projects_dir).glob("*"))

    def test_create_with_git_url_error_does_not_leak_password(
        self, client, db_session
    ):
        """clone 失败的错误消息不应泄露 URL 中的密码。"""
        headers = _auth_headers(db_session)
        payload = {
            "name": "private",
            "git_url": "https://user:supersecret@example.com/org/private.git",
        }
        with patch(
            "app.routers.projects.clone_repo",
            side_effect=RuntimeError(
                "Authentication failed for https://user:supersecret@example.com/org/private.git"
            ),
        ):
            resp = client.post("/projects", json=payload, headers=headers)

        assert resp.status_code == 400
        assert "supersecret" not in resp.json()["detail"]

    def test_create_with_git_url_extracted_name_too_long_rejected(
        self, client, db_session, _tmp_projects_dir
    ):
        """从 URL 提取的仓库名超过 128 字符时拒绝创建。"""
        headers = _auth_headers(db_session)
        long_repo = "a" * 200
        payload = {"git_url": f"https://example.com/user/{long_repo}.git"}
        with patch(
            "app.routers.projects.clone_repo", side_effect=_fake_clone()
        ) as mock_clone:
            resp = client.post("/projects", json=payload, headers=headers)

        assert resp.status_code == 400
        assert "128" in resp.json()["detail"]
        mock_clone.assert_not_called()
        assert db_session.query(ProjectModel).count() == 0

    def test_create_with_git_url_very_long_url_rejected(self, client, db_session):
        """超长 git URL（>2048 字符）应被拒绝。"""
        headers = _auth_headers(db_session)
        payload = {"name": "long", "git_url": "https://example.com/" + "a" * 3000}
        with patch(
            "app.routers.projects.clone_repo", side_effect=_fake_clone()
        ) as mock_clone:
            resp = client.post("/projects", json=payload, headers=headers)

        assert resp.status_code == 400
        mock_clone.assert_not_called()

    def test_create_with_git_url_env_credentials_injected(
        self, client, db_session, monkeypatch
    ):
        """环境变量 GIT_USERNAME/GIT_PASSWORD 应注入到传给 clone 的 URL。"""
        monkeypatch.setenv("GIT_USERNAME", "bot")
        monkeypatch.setenv("GIT_PASSWORD", "secret")
        headers = _auth_headers(db_session)
        payload = {"name": "myapp", "git_url": "https://example.com/user/myapp.git"}
        with patch(
            "app.routers.projects.clone_repo", side_effect=_fake_clone()
        ) as mock_clone:
            resp = client.post("/projects", json=payload, headers=headers)

        assert resp.status_code == 201
        from urllib.parse import urlsplit

        called_url = mock_clone.call_args.args[0]
        parts = urlsplit(called_url)
        assert parts.username == "bot"
        assert parts.password == "secret"


# ---------------------------------------------------------------------------
# MCP create_project 工具测试
# ---------------------------------------------------------------------------


class TestMCPCreateProjectGitUrl:
    def test_create_project_with_git_url(self, mcp_tools, _tmp_projects_dir):
        """MCP create_project 支持 git_url，name 缺省时取仓库名。"""
        create_project = mcp_tools["create_project"]
        with patch(
            "app.mcp.tools.clone_repo", side_effect=_fake_clone("Dockerfile")
        ):
            result = create_project(name=None, git_url="https://example.com/user/myapp.git")

        assert result["name"] == "myapp"
        project_dir = pathlib.Path(_tmp_projects_dir) / result["id"]
        assert (project_dir / ".git").is_dir()
        assert (project_dir / "Dockerfile").exists()

    def test_create_project_with_git_url_clone_failure_rolls_back(
        self, mcp_tools, _tmp_projects_dir, db_session
    ):
        """MCP create_project clone 失败抛 RuntimeError 且回滚。"""
        create_project = mcp_tools["create_project"]
        with patch(
            "app.mcp.tools.clone_repo",
            side_effect=RuntimeError("Repository not found"),
        ):
            with pytest.raises(RuntimeError, match="Repository not found"):
                create_project(
                    name="myapp", git_url="https://example.com/user/myapp.git"
                )

        assert db_session.query(ProjectModel).count() == 0
        assert not list(pathlib.Path(_tmp_projects_dir).glob("*"))

    def test_create_project_with_git_url_missing_files_get_templates(
        self, mcp_tools, _tmp_projects_dir
    ):
        """MCP create_project clone 后仓库缺 Dockerfile 时补默认模板。"""
        create_project = mcp_tools["create_project"]
        with patch(
            "app.mcp.tools.clone_repo", side_effect=_fake_clone("README.md")
        ):
            result = create_project(
                name="emptyrepo", git_url="https://example.com/user/empty.git"
            )

        project_dir = pathlib.Path(_tmp_projects_dir) / result["id"]
        assert (project_dir / "README.md").exists()
        assert (project_dir / "Dockerfile").exists()
        assert (project_dir / "docker-compose.yaml").exists()

    def test_create_project_invalid_git_url_rejected(self, mcp_tools, db_session):
        """MCP create_project 收到非法 git_url 抛 RuntimeError。"""
        create_project = mcp_tools["create_project"]
        with patch("app.mcp.tools.clone_repo", side_effect=_fake_clone()) as mock_clone:
            with pytest.raises(RuntimeError):
                create_project(name="bad", git_url="--upload-pack=evil")

        mock_clone.assert_not_called()
        assert db_session.query(ProjectModel).count() == 0


# ---------------------------------------------------------------------------
# Bug 复现：git 仓库自带 docker-compose.yml（.yml 扩展名）未被识别
# ---------------------------------------------------------------------------


class TestRESTComposeYmlRecognition:
    """bug 复现：clone 的仓库自带 docker-compose.yml 时应识别，而非补默认模板。"""

    def test_create_with_git_url_repo_docker_compose_yml_not_overwritten(
        self, client, db_session, _tmp_projects_dir
    ):
        """仓库自带 docker-compose.yml 时：保留仓库版本，且不生成默认 docker-compose.yaml。"""
        headers = _auth_headers(db_session)
        payload = {"name": "withyml", "git_url": "https://example.com/user/withyml.git"}
        with patch(
            "app.routers.projects.clone_repo",
            side_effect=_fake_clone("docker-compose.yml"),
        ):
            resp = client.post("/projects", json=payload, headers=headers)

        assert resp.status_code == 201
        project_dir = pathlib.Path(_tmp_projects_dir) / resp.json()["id"]
        compose_yml = project_dir / "docker-compose.yml"
        assert compose_yml.exists()
        assert "cloned from" in compose_yml.read_text(encoding="utf-8")
        assert not (project_dir / "docker-compose.yaml").exists()


class TestMCPComposeYmlRecognition:
    """bug 复现：MCP create_project 同样应识别仓库自带的 docker-compose.yml。"""

    def test_create_project_with_git_url_repo_docker_compose_yml_recognized(
        self, mcp_tools, _tmp_projects_dir
    ):
        create_project = mcp_tools["create_project"]
        with patch(
            "app.mcp.tools.clone_repo",
            side_effect=_fake_clone("docker-compose.yml"),
        ):
            result = create_project(
                name="withyml", git_url="https://example.com/user/withyml.git"
            )

        project_dir = pathlib.Path(_tmp_projects_dir) / result["id"]
        assert (project_dir / "docker-compose.yml").exists()
        assert "cloned from" in (
            project_dir / "docker-compose.yml"
        ).read_text(encoding="utf-8")
        assert not (project_dir / "docker-compose.yaml").exists()
