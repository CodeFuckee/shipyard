"""
测试 .gitlab-ci.yml — 验证 CI 部署脚本中端口映射正确，shell 语法合法。

复现 bug 1：deploy_to_synology job 中 docker run -p 写死映射到容器
8000 端口（FastAPI/uvicorn），绕过 nginx，导致前端页面返回 404。

复现 bug 2：shell 多行续行符 \\ 中间插入 # 注释，破坏续行链，
导致 docker run 参数丢失。
"""

import re
from pathlib import Path

import pytest
import yaml

# 项目根目录
BACKEND_ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = BACKEND_ROOT.parent
CI_FILE = PROJECT_ROOT / ".gitlab-ci.yml"


class TestGitlabCIPortMapping:
    """验证 .gitlab-ci.yml 中的 docker run -p 端口映射指向 nginx (80)。"""

    # ------------------------------------------------------------------
    # 复现测试：deploy job docker run 映射到 8000 而不是 80
    # ------------------------------------------------------------------

    def test_deploy_docker_run_maps_to_nginx_port_80(self):
        """复现 bug：deploy_to_synology 中 docker run -p 映射到 8000 而非 80。

        容器内部架构：
        - nginx (port 80) → 前端静态文件 + API 代理 → uvicorn (127.0.0.1:8000)
        - uvicorn 绑定在 127.0.0.1:8000，不对外暴露

        如果 docker run -p 映射到 8000，请求绕过 nginx 直接打到 FastAPI。
        """
        if not CI_FILE.exists():
            pytest.skip(f"文件不存在: {CI_FILE}")

        content = CI_FILE.read_text(encoding="utf-8")

        # 找到 docker run 命令中的端口映射
        # 匹配: -p ${VAR:-default}:PORT 或 -p host:container
        port_mappings = re.findall(
            r'-p\s+\$\{[^}]+\}:\d+', content
        )
        # 也匹配纯数字的映射（如果存在的话）
        port_mappings += re.findall(
            r'-p\s+\d+:\d+', content
        )

        assert port_mappings, (
            ".gitlab-ci.yml 中未找到 docker run 端口映射。\n"
            "如果部署方式已变更，请更新本测试。"
        )

        # 端口映射必须指向 nginx (80)，不能是 uvicorn (8000)
        bad_mappings = []
        for mapping in port_mappings:
            # 提取容器端口（冒号后的数字）
            match = re.search(r':(\d+)', mapping)
            if match:
                container_port = match.group(1)
                if container_port == "8000":
                    bad_mappings.append(mapping)

        assert bad_mappings == [], (
            f".gitlab-ci.yml 中 docker run -p 端口映射错误！\n"
            f"以下映射指向了容器 8000 端口（FastAPI/uvicorn）：\n"
            f"  {bad_mappings}\n\n"
            f"应改为映射到 80 端口（nginx）。\n"
            f"原因：容器内部 nginx 监听 80 端口，uvicorn 绑定在 127.0.0.1:8000。\n"
            f"映射到 8000 会绕过 nginx，请求直接打到 FastAPI → 404 Not Found。"
        )

    # ------------------------------------------------------------------
    # 复现测试：项目根目录缺少 .dockerignore 导致构建上下文过大
    # ------------------------------------------------------------------

    def test_project_root_has_dockerignore_with_excludes(self):
        """复现 bug：项目根目录无 .dockerignore，docker build 上下文 456MB，
        包含 .git/、data/ 等无关大文件，NAS 上资源耗尽导致构建失败。

        All-in-One Dockerfile.cn 只需要 frontend/ 和 backend/ 目录，
        其他大文件/目录应排除。
        """
        root_dockerignore = PROJECT_ROOT / ".dockerignore"
        if not root_dockerignore.exists():
            # 允许 CI_FILE 指向的构建上下文中存在 .dockerignore
            # 实际 CI 在项目根目录构建，需要该文件
            pass  # 继续检查

        # 验证 CI 中的 docker build 命令会触发上下文大小问题
        content = CI_FILE.read_text(encoding="utf-8")

        # 找到 docker build 命令
        build_match = re.search(
            r'docker\s+build\b.*?-f\s+\S+.*?\.\.', content
        )
        if build_match:
            cmd = build_match.group(0)
            # 如果构建上下文是 ..（项目根），必须要有 .dockerignore
            if ".." in cmd.split()[-1] if cmd.split() else False:
                pass  # 上下文是项目根

        # 核心断言：项目根目录必须存在 .dockerignore
        assert root_dockerignore.exists(), (
            f"项目根目录缺少 .dockerignore 文件！\n"
            f"当前 docker build 上下文为项目根目录，包含了 .git/、\n"
            f"data/、frontend/build/ 等大量无关文件（CI 中实测 456MB），\n"
            f"导致 NAS Docker daemon 资源耗尽而构建失败（unknown failure）。\n\n"
            f"修复：在 {PROJECT_ROOT}/.dockerignore 中添加排除规则。"
        )

        # 验证 .dockerignore 排除了关键大目录
        ignores = root_dockerignore.read_text(encoding="utf-8")
        required_excludes = [".git", "data", "__pycache__"]
        missing = [e for e in required_excludes if e not in ignores]

        assert missing == [], (
            f"项目根 .dockerignore 缺少必要的排除规则: {missing}\n"
            f"这些目录/文件不应包含在 docker build 上下文中。\n"
            f"当前内容:\n{ignores}"
        )

    def test_deploy_job_exists_and_has_port_mapping(self):
        """验证 deploy_to_synology job 存在并包含端口映射。"""
        if not CI_FILE.exists():
            pytest.skip(f"文件不存在: {CI_FILE}")

        data = yaml.safe_load(CI_FILE.read_text(encoding="utf-8"))

        deploy_job = data.get("deploy_to_synology")
        assert deploy_job is not None, (
            "找不到 deploy_to_synology job，部署配置可能已变更，请更新本测试。"
        )

        script = deploy_job.get("script", "")
        # script 可能是字符串或列表
        if isinstance(script, list):
            script = "\n".join(script)

        assert "-p " in script, (
            "deploy_to_synology 的 script 中未找到 docker run -p 端口映射。\n"
            "部署方式可能已变更，请更新本测试。"
        )

    # ------------------------------------------------------------------
    # 复现测试：shell 续行符 \\ 中间不能有 # 注释
    # ------------------------------------------------------------------

    def test_no_comment_breaks_shell_line_continuation(self):
        """复现 bug：shell \\ 续行符中间插入 # 注释，导致续行断裂。

        在 shell 中，\\ 会移除换行符并拼接下一行内容。如果拼接后的行
        以 # 开头，则 # 及之后的所有内容（包括后续续行拼接的部分）
        都会被视为注释，导致：
        - docker run 参数被吞掉（包括镜像名）
        - 剩余的续行参数被当作独立命令执行（如 -p: command not found）
        """
        if not CI_FILE.exists():
            pytest.skip(f"文件不存在: {CI_FILE}")

        content = CI_FILE.read_text(encoding="utf-8")
        lines = content.split("\n")

        # 检测模式：一行以 \ 结尾（续行），下一行以 # 开头（注释）
        # 这种模式会破坏 shell 多行命令
        bad_lines = []
        for i, line in enumerate(lines):
            stripped = line.rstrip()
            if stripped.endswith("\\"):
                # 找下一非空行
                next_i = i + 1
                while next_i < len(lines) and lines[next_i].strip() == "":
                    next_i += 1
                if next_i < len(lines):
                    next_line = lines[next_i].lstrip()
                    if next_line.startswith("#"):
                        bad_lines.append(
                            f"  第 {i + 1} 行（以 \\ 结尾）→ "
                            f"第 {next_i + 1} 行（以 # 开头）"
                        )

        assert bad_lines == [], (
            f".gitlab-ci.yml 中 shell 续行符 \\\\ 与 # 注释冲突！\n"
            f"以下位置的 \\\\ 续行紧接着 # 注释，会破坏 shell 多行命令：\n"
            + "\n".join(bad_lines) + "\n\n"
            f"修复方法：将注释移到 docker run 命令之前，或写在 -p 同一行末尾。\n"
            f"不要在 \\\\ 续行链中间插入独立的注释行。"
        )

    # ------------------------------------------------------------------
    # 复现测试：build_images 使用了错误的 Dockerfile
    # ------------------------------------------------------------------

    def test_build_images_uses_all_in_one_dockerfile(self):
        """验证 backend:build_images 使用 All-in-One Dockerfile（含 nginx + supervisord）
        而非 backend/Dockerfile.cn（纯后端，无 nginx）。

        Flutter 前端由 CI frontend:build_web job 在 gitlab-runner 机器上编译
        （不再在 Docker 容器内编译），根 Dockerfile.cn 与 Dockerfile.nas.cn 一样
        不含 Flutter SDK 编译阶段，仅 COPY 构建产物，NAS 上可直接构建。
        """
        if not CI_FILE.exists():
            pytest.skip(f"文件不存在: {CI_FILE}")

        content = CI_FILE.read_text(encoding="utf-8")

        # 查找 docker build 命令中的 -f 参数
        found_good = []
        found_wrong = []
        for match in re.finditer(
            r'docker\s+build\b[^\n]*?-f\s+(\S+)', content
        ):
            f_arg = match.group(1)

            # 项目根目录的 All-in-One Dockerfile（含 nginx + supervisord）
            if f_arg == "../Dockerfile.cn":
                found_good.append(
                    f"  -f {f_arg} → All-in-One（前端由 CI frontend:build_web 编译）"
                )
            elif f_arg == "../Dockerfile.nas.cn":
                found_good.append(
                    f"  -f {f_arg} → NAS 专用版（下载预构建前端）"
                )
            elif f_arg == "Dockerfile.cn" or f_arg == "./Dockerfile.cn":
                # deploy_to_synology fallback：工作目录为仓库根，同样指向根目录 All-in-One
                found_good.append(
                    f"  -f {f_arg} → 根目录 All-in-One（当前工作目录为仓库根）"
                )
            elif "backend/Dockerfile.cn" in f_arg:
                found_wrong.append(
                    f"  -f {f_arg} → 纯后端 Dockerfile，缺少 nginx，会导致 502"
                )

        assert found_wrong == [], (
            f".gitlab-ci.yml 中 backend:build_images 使用了纯后端 Dockerfile！\n"
            f"{chr(10).join(found_wrong)}\n\n"
            f"应使用项目根目录的 All-in-One Dockerfile.cn（含 nginx + supervisord），\n"
            f"而非 backend/Dockerfile.cn（纯后端，无 nginx，前端 502）。"
        )

        assert found_good != [], (
            f".gitlab-ci.yml 中未找到 All-in-One Dockerfile 引用。\n"
            f"backend:build_images 应使用 -f ../Dockerfile.cn 或 -f ../Dockerfile.nas.cn"
        )

        # 验证根 Dockerfile.cn 不再包含 Flutter SDK 编译阶段
        # （前端由 CI frontend:build_web 在 runner 上编译，防止回归）
        # 注意：不能简单匹配 "flutter build" —— 文件头注释会说明手动构建
        # 命令，需精确匹配实际的编译阶段（AS flutter-build / RUN flutter build）
        root_dockerfile = PROJECT_ROOT / "Dockerfile.cn"
        if root_dockerfile.exists():
            dockerfile_content = root_dockerfile.read_text(encoding="utf-8")
            assert "AS flutter-build" not in dockerfile_content and \
                "RUN flutter build" not in dockerfile_content, (
                "根 Dockerfile.cn 不应再包含 Flutter SDK 编译阶段！\n"
                "Flutter 前端已改为由 CI frontend:build_web job 在\n"
                "gitlab-runner 机器上直接编译，Dockerfile.cn 应仅 COPY\n"
                "frontend/build/web 构建产物（NAS 资源不足问题已消除）。"
            )
