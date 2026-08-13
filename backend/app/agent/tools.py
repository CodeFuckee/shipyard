"""Agent 工具 — 将 backend/skills 的两个 skill 封装为 langchain 工具。

- docker_mirror_pull：解析镜像名 → 逐个尝试国内镜像源 → 成功即停止
  （对应 backend/skills/docker-mirror-pull/SKILL.md）
- docker_pull_from_file：解析 Dockerfile / docker-compose.yml 提取镜像，
  逐个拉取并汇总（对应 backend/skills/docker-pull-from-file/SKILL.md，
  复用其 extract_images.py 脚本完成解析）
"""

import json
import re
import subprocess
import sys
from pathlib import Path

from langchain_core.tools import tool

from app.agent.executor import DockerSocketPuller, ImagePuller
from app.agent.mirror_sources import get_mirror_prefixes

# 模块级执行器单例；测试中替换为 FakePuller（见 tests/test_agent_tools.py）
puller: ImagePuller = DockerSocketPuller()

# extract_images.py 脚本路径：backend/skills/docker-pull-from-file/extract_images.py
_EXTRACT_SCRIPT = (
    Path(__file__).resolve().parent.parent.parent
    / "skills"
    / "docker-pull-from-file"
    / "extract_images.py"
)

# Docker 镜像名合法字符（含 registry:port / tag / digest），用于防注入校验
_IMAGE_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/:@-]*$")
_MAX_IMAGE_LEN = 512

# pull_single_image 成功返回的前缀（供 docker_pull_from_file 统计成功数）
_SINGLE_SUCCESS_PREFIX = "✅ 镜像拉取成功"


def validate_image_name(image_name: str) -> str | None:
    """校验镜像名，返回错误描述（None = 合法）。"""
    if not image_name or not image_name.strip():
        return "镜像名为空"
    name = image_name.strip()
    if len(name) > _MAX_IMAGE_LEN:
        return f"镜像名过长（>{_MAX_IMAGE_LEN} 字符）"
    if not _IMAGE_NAME_RE.match(name):
        return "镜像名含非法字符（仅允许字母、数字及 . _ / : @ -）"
    return None


def pull_single_image(image_name: str, mirror_prefixes: list[str] | None = None) -> str:
    """尝试从多个镜像源拉取单个镜像（docker_mirror_pull 的实现函数）。

    供工具与 docker_pull_from_file 共用；成功即停止，全部失败返回错误摘要。
    """
    error = validate_image_name(image_name)
    if error:
        return f"❌ 参数错误：{error}"

    name = image_name.strip()
    sources = mirror_prefixes or get_mirror_prefixes()
    if not sources:
        return "❌ 没有可用的镜像源（AGENT_MIRROR_PREFIXES 为空且默认列表为空）"

    attempts = []
    for prefix in sources:
        full = f"{prefix}/{name}"
        code, message = puller.pull(full, name)
        attempts.append(f"- {prefix}: {message}")
        if code == 0:
            return (
                f"{_SINGLE_SUCCESS_PREFIX}（通过镜像源 {prefix}）\n"
                f"  镜像: {name}\n"
                + "\n".join(attempts)
            )
    return "❌ 所有镜像源均拉取失败：\n" + "\n".join(attempts)


@tool
def docker_mirror_pull(image_name: str, mirror_prefixes: list[str] | None = None) -> str:
    """从国内镜像源拉取单个 Docker 镜像（自动切换镜像源，无需用户执行 docker 命令）。

    参数:
      image_name: 要拉取的镜像名，可含 tag（如 nginx:1.25、
                  langgenius/dify-plugin-daemon:0.6.3-local），官方镜像可省略 library/ 前缀。
      mirror_prefixes: 可选，指定优先尝试的镜像源列表（域名形式，
                  如 ["docker.1ms.run"]）；缺省时按内置可用镜像源列表顺序逐个尝试，成功即停止。
    返回: 中文结果摘要（成功时含实际生效的镜像源）。
    """
    return pull_single_image(image_name, mirror_prefixes)


def _run_extract_script(file_path: str) -> list[dict]:
    """调用 extract_images.py 提取镜像列表（JSON），失败抛 ValueError。"""
    try:
        result = subprocess.run(
            [sys.executable, str(_EXTRACT_SCRIPT), file_path],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        raise ValueError("镜像解析超时（>30 秒）") from None
    except OSError as exc:
        raise ValueError(f"无法执行镜像解析脚本: {exc}") from None
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        raise ValueError(f"镜像解析失败: {detail}")
    try:
        items = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise ValueError(f"镜像解析输出异常: {exc}") from None
    return items


def pull_images_from_file(file_path: str) -> str:
    """从 Dockerfile / docker-compose.yml 提取镜像并批量拉取（docker_pull_from_file 的实现函数）。

    供 langchain 工具与 MCP 注册的 skill 工具共用（issue #25）。
    """
    try:
        items = _run_extract_script(file_path)
    except ValueError as exc:
        return f"❌ {exc}"

    if not items:
        return "未从文件中提取到任何镜像（仅支持 Dockerfile 的 FROM 指令与 docker-compose 的 image 字段）"

    seen: set[str] = set()
    fixed: list[str] = []
    variable: list[str] = []
    for item in items:
        image = (item.get("image") or "").strip()
        if not image or image in seen:
            continue
        seen.add(image)
        (variable if item.get("type") == "variable" else fixed).append(image)

    fixed = sorted(fixed)
    variable = sorted(variable)

    lines = [f"📦 从 {file_path} 提取到 {len(fixed) + len(variable)} 个镜像，开始逐个拉取：", ""]
    ok_count = 0
    for image in fixed:
        report = pull_single_image(image)
        if report.startswith(_SINGLE_SUCCESS_PREFIX):
            ok_count += 1
        lines.append(report)
        lines.append("")
    for image in variable:
        lines.append(f"⚠️ 镜像含变量占位符（需确认后手动处理）: {image}")
        lines.append("")

    lines.append(f"📊 批量拉取完成：✅ 成功 {ok_count}/{len(fixed)}，⚠️ 变量占位 {len(variable)} 个")
    return "\n".join(lines)


@tool
def docker_pull_from_file(file_path: str) -> str:
    """从 Dockerfile 或 docker-compose.yml 文件中提取所有 Docker 镜像并批量拉取。

    参数:
      file_path: 文件路径（Dockerfile / docker-compose.yml / docker-compose.yaml）。
    说明:
      - 自动跳过 scratch 与纯 build（无 image 字段）的服务
      - 同一镜像只拉取一次；单个失败不中断，最后汇总报告
      - 含变量占位符的镜像（如 ${BASE_IMAGE}）单独标注，可能无法直接拉取
    返回: 中文汇总报告（每个镜像的成功/失败与生效镜像源）。
    """
    return pull_images_from_file(file_path)
