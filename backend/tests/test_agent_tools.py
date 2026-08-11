"""镜像拉取 Agent 工具 — docker_mirror_pull / docker_pull_from_file / 镜像源。

覆盖：
- 正常路径：单镜像首个源成功、多源逐个尝试直到成功、批量提取+拉取汇总、去重
- 边界情况：全部镜像源失败、非法镜像名（空/超长/非法字符）不执行拉取、
  无可用镜像源、自定义镜像源列表、打标签失败仍计成功、
  文件解析失败/无镜像/含变量占位、解析脚本异常
"""

import pytest

from app.agent import mirror_sources, tools
from app.agent.tools import docker_mirror_pull, docker_pull_from_file, pull_single_image


class FakePuller:
    """可配置的假执行器：results 为 (full_image, original_image) → (code, message)。"""

    def __init__(self, results=None):
        self.results = results or {}
        self.calls = []

    def pull(self, full_image, original_image=None):
        self.calls.append((full_image, original_image))
        return self.results.get(full_image, (1, "默认失败"))


@pytest.fixture(autouse=True)
def fake_puller(monkeypatch):
    puller = FakePuller()
    monkeypatch.setattr(tools, "puller", puller)
    return puller


def _success(full_image):
    return {full_image: (0, f"拉取成功: {full_image}")}


# --- 镜像名校验 ---


@pytest.mark.parametrize(
    "name",
    [
        "nginx:1.25",
        "nginx",
        "langgenius/dify-plugin-daemon:0.6.3-local",
        "library/nginx:latest",
        "registry.example.com:5000/app/img:v1",
        "img@sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
        "ubuntu",
    ],
)
def test_valid_image_names(name):
    assert tools.validate_image_name(name) is None


@pytest.mark.parametrize(
    "name,reason",
    [
        ("", "空"),
        ("   ", "空白"),
        ("-nginx", "以 - 开头"),
        ("nginx;rm -rf /", "含分号"),
        ("nginx$(id)", "含 shell 符号"),
        ("nginx 1.25", "含空格"),
        ("nginx:1.25!", "含非法字符"),
        ("x" * 513, "超长"),
    ],
)
def test_invalid_image_names(name, reason):
    error = tools.validate_image_name(name)
    assert error is not None, f"应当拒绝非法镜像名 {name!r}（{reason}）"


# --- docker_mirror_pull ---


def test_pull_success_on_first_source(fake_puller):
    fake_puller.results = _success("docker.1ms.run/nginx:1.25")
    report = docker_mirror_pull.invoke({"image_name": "nginx:1.25"})
    assert "✅ 镜像拉取成功" in report
    assert "docker.1ms.run" in report
    assert fake_puller.calls == [("docker.1ms.run/nginx:1.25", "nginx:1.25")]


def test_pull_falls_back_to_next_source(fake_puller):
    fake_puller.results = {
        "docker.1ms.run/nginx:1.25": (1, "失败: 超时"),
        "docker.m.daocloud.io/nginx:1.25": (1, "失败: 404"),
        "dockerproxy.com/nginx:1.25": (0, "拉取成功: dockerproxy.com/nginx:1.25"),
    }
    report = docker_mirror_pull.invoke({"image_name": "nginx:1.25"})
    assert "✅ 镜像拉取成功" in report
    assert "dockerproxy.com" in report
    assert len(fake_puller.calls) == 3


def test_pull_all_sources_fail(fake_puller):
    report = docker_mirror_pull.invoke({"image_name": "nginx:1.25"})
    assert "❌ 所有镜像源均拉取失败" in report
    # 默认列表应全部尝试过
    assert len(fake_puller.calls) == len(mirror_sources.DEFAULT_MIRROR_PREFIXES)


def test_pull_custom_mirror_prefixes(fake_puller):
    fake_puller.results = _success("hub.example.com/nginx:1.25")
    report = docker_mirror_pull.invoke(
        {"image_name": "nginx:1.25", "mirror_prefixes": ["hub.example.com"]}
    )
    assert "✅ 镜像拉取成功" in report
    assert fake_puller.calls == [("hub.example.com/nginx:1.25", "nginx:1.25")]


def test_pull_invalid_name_does_not_call_puller(fake_puller):
    report = docker_mirror_pull.invoke({"image_name": "nginx; rm -rf /"})
    assert "❌ 参数错误" in report
    assert fake_puller.calls == []


def test_pull_empty_name(fake_puller):
    report = docker_mirror_pull.invoke({"image_name": ""})
    assert "❌ 参数错误" in report
    assert fake_puller.calls == []


def test_pull_success_even_if_tag_failed(fake_puller):
    """打标签失败仅警告，拉取本身仍算成功（与 skill pull.py 行为一致）。"""
    fake_puller.results = {"docker.1ms.run/nginx:1.25": (0, "拉取成功: docker.1ms.run/nginx:1.25；打标签失败: 网络问题")}
    report = docker_mirror_pull.invoke({"image_name": "nginx:1.25"})
    assert "✅ 镜像拉取成功" in report


# --- docker_pull_from_file ---


@pytest.fixture
def fake_extract(monkeypatch):
    def install(items):
        monkeypatch.setattr(tools, "_run_extract_script", lambda path: items)
    return install


def test_pull_from_file_batch(fake_puller, fake_extract):
    fake_extract(
        [
            {"image": "nginx:1.25", "type": "fixed", "source_line": "FROM nginx:1.25"},
            {"image": "node:20-alpine", "type": "fixed", "source_line": "FROM node:20-alpine AS builder"},
        ]
    )
    fake_puller.results = {
        "docker.1ms.run/nginx:1.25": (0, "拉取成功: docker.1ms.run/nginx:1.25"),
        # node 在所有镜像源上失败，验证部分失败汇总
    }
    report = docker_pull_from_file.invoke({"file_path": "Dockerfile"})
    assert "提取到 2 个镜像" in report
    assert "✅ 成功 1/2" in report
    assert "✅ 镜像拉取成功" in report
    assert "❌ 所有镜像源均拉取失败" in report


def test_pull_from_file_dedup(fake_puller, fake_extract):
    fake_extract(
        [
            {"image": "nginx:1.25", "type": "fixed", "source_line": "a"},
            {"image": "nginx:1.25", "type": "fixed", "source_line": "b"},
        ]
    )
    report = docker_pull_from_file.invoke({"file_path": "docker-compose.yml"})
    assert "提取到 1 个镜像" in report
    assert len(fake_puller.calls) == len(mirror_sources.DEFAULT_MIRROR_PREFIXES)  # 只拉一次（全部失败）


def test_pull_from_file_variable_images(fake_puller, fake_extract):
    fake_extract(
        [
            {"image": "${BASE_IMAGE}", "type": "variable", "source_line": "FROM ${BASE_IMAGE}"},
            {"image": "nginx:1.25", "type": "fixed", "source_line": "FROM nginx:1.25"},
        ]
    )
    fake_puller.results = _success("docker.1ms.run/nginx:1.25")
    report = docker_pull_from_file.invoke({"file_path": "Dockerfile"})
    assert "变量占位" in report
    assert "${BASE_IMAGE}" in report
    assert "✅ 成功 1/1" in report


def test_pull_from_file_no_images(fake_puller, fake_extract):
    fake_extract([])
    report = docker_pull_from_file.invoke({"file_path": "Dockerfile"})
    assert "未从文件中提取到任何镜像" in report
    assert fake_puller.calls == []


def test_pull_from_file_missing_file(fake_puller, monkeypatch):
    monkeypatch.setattr(
        tools,
        "_run_extract_script",
        lambda path: (_ for _ in ()).throw(ValueError("镜像解析失败: 错误: 文件不存在: /no/such/Dockerfile")),
    )
    report = docker_pull_from_file.invoke({"file_path": "/no/such/Dockerfile"})
    assert "❌" in report
    assert "文件不存在" in report
    assert fake_puller.calls == []


def test_pull_from_file_extract_script_crash(fake_puller, monkeypatch):
    monkeypatch.setattr(
        tools, "_run_extract_script", lambda path: (_ for _ in ()).throw(ValueError("镜像解析失败: 无法识别文件类型"))
    )
    report = docker_pull_from_file.invoke({"file_path": "unknown.txt"})
    assert "❌" in report
    assert fake_puller.calls == []


def test_run_extract_script_ok(tmp_path, monkeypatch):
    """真实调用 extract_images.py 脚本（backend/skills 中）。"""
    dockerfile = tmp_path / "Dockerfile"
    dockerfile.write_text("FROM nginx:1.25\nFROM node:20-alpine AS builder\n")
    items = tools._run_extract_script(str(dockerfile))
    assert {i["image"] for i in items} == {"nginx:1.25", "node:20-alpine"}


def test_run_extract_script_missing_file():
    with pytest.raises(ValueError, match="文件不存在"):
        tools._run_extract_script("/no/such/file/Dockerfile")


# --- 镜像源 ---


def test_default_mirror_prefixes(monkeypatch):
    monkeypatch.setattr(mirror_sources, "AGENT_MIRROR_PREFIXES", "")
    assert mirror_sources.get_mirror_prefixes() == mirror_sources.DEFAULT_MIRROR_PREFIXES


def test_env_mirror_prefixes_override(monkeypatch):
    monkeypatch.setattr(mirror_sources, "AGENT_MIRROR_PREFIXES", "a.example.com, b.example.com")
    assert mirror_sources.get_mirror_prefixes() == ["a.example.com", "b.example.com"]


def test_env_mirror_prefixes_ignores_blank(monkeypatch):
    monkeypatch.setattr(mirror_sources, "AGENT_MIRROR_PREFIXES", "a.example.com, ,")
    assert mirror_sources.get_mirror_prefixes() == ["a.example.com"]


def test_no_available_sources(fake_puller, monkeypatch):
    monkeypatch.setattr(mirror_sources, "AGENT_MIRROR_PREFIXES", "")
    monkeypatch.setattr(mirror_sources, "DEFAULT_MIRROR_PREFIXES", [])
    monkeypatch.setattr(tools, "get_mirror_prefixes", lambda: [])
    report = pull_single_image("nginx:1.25")
    assert "没有可用的镜像源" in report
    assert fake_puller.calls == []
