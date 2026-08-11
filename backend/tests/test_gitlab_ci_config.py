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

if not CI_FILE.exists():
    # GitHub 镜像仓库由 sync_to_github 刻意剔除 .gitlab-ci.yml
    # （镜像历史由 sync job 全权维护），本测试仅对 GitLab 仓库有意义，
    # 镜像仓库上整个模块跳过。
    pytest.skip(f"未找到 {CI_FILE}（GitHub 镜像剔除该文件），跳过 CI 配置测试",
                allow_module_level=True)


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
        """验证 build_images（原 backend:build_images）使用 All-in-One Dockerfile（含 nginx + supervisord）
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
            f".gitlab-ci.yml 中 build_images 使用了纯后端 Dockerfile！\n"
            f"{chr(10).join(found_wrong)}\n\n"
            f"应使用项目根目录的 All-in-One Dockerfile.cn（含 nginx + supervisord），\n"
            f"而非 backend/Dockerfile.cn（纯后端，无 nginx，前端 502）。"
        )

        assert found_good != [], (
            f".gitlab-ci.yml 中未找到 All-in-One Dockerfile 引用。\n"
            f"build_images 应使用 -f ../Dockerfile.cn 或 -f ../Dockerfile.nas.cn"
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


# ------------------------------------------------------------------
# 复现 bug：.dockerignore 排除 frontend/build/web → 构建失败 → CI 假绿 → 502
# ------------------------------------------------------------------

def _dockerignore_match(pattern: str, path: str) -> bool:
    """简化版 dockerignore 规则匹配：支持 * 与 **，末尾 / 表示目录。

    - 规则不含 / 时匹配路径中的任意一段（如 *.pyc 匹配任意层级）
    - ** 可跨目录匹配
    - fnmatch 的 * 会跨 /，对本项目单层路径场景结果一致，足够精确
    """
    import fnmatch

    pattern = pattern.rstrip("/")
    path = path.rstrip("/")
    if not pattern:
        return False

    if "**" in pattern:
        regex = re.escape(pattern).replace(r"\*\*", ".*").replace(r"\*", "[^/]*")
        return re.fullmatch(regex, path) is not None

    if "/" not in pattern:
        return fnmatch.fnmatch(path, pattern) or any(
            fnmatch.fnmatch(seg, pattern) for seg in path.split("/")
        )

    return fnmatch.fnmatch(path, pattern)


class TestDockerignoreKeepsBuildProducts:
    """验证 .dockerignore 不排除 Dockerfile.cn 需要的构建产物。

    复现 bug：.dockerignore 曾包含 `frontend/build/`（整目录排除），而
    Flutter 移出容器后 Dockerfile.cn 需要 `COPY frontend/build/web`。
    构建必然失败（ERROR: "/frontend/build/web": not found），但
    .backend_setup 的 set +e 吞掉了失败 → CI 假绿 → deploy 用 NAS 上
    残留的旧镜像部署 → 用户访问 502。
    """

    @staticmethod
    def _is_excluded(rules, target):
        """按顺序应用 dockerignore 规则（! 前缀重新包含），返回最终是否排除。"""
        excluded = False
        for rule in rules:
            if rule.startswith("!"):
                if _dockerignore_match(rule[1:], target):
                    excluded = False
            else:
                if _dockerignore_match(rule, target):
                    excluded = True
        return excluded

    def test_dockerignore_keeps_frontend_build_web(self):
        """.dockerignore 不得排除 Dockerfile.cn 的 COPY 源（web/ 与 web.tar.gz）。"""
        dockerignore = PROJECT_ROOT / ".dockerignore"
        if not dockerignore.exists():
            pytest.skip(f"文件不存在: {dockerignore}")

        rules = [
            line.strip() for line in dockerignore.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.strip().startswith("#")
        ]

        # Dockerfile.cn 的 COPY 源（目录 COPY 或打包后单文件 COPY，两种都要保留）
        targets = ["frontend/build/web", "frontend/build/web.tar.gz"]
        for target in targets:
            excluded = self._is_excluded(rules, target)
            assert not excluded, (
                f".dockerignore 排除了 Dockerfile.cn 需要的构建产物 {target}！\n"
                f"这会导致 docker build 的 COPY 失败：\n"
                f"  ERROR: failed to calculate checksum ... \"{target}\": not found\n\n"
                f"修复方法：排除 build 下除 web 产物外的中间产物，并重新包含 web：\n"
                f"  frontend/build/*\n"
                f"  !frontend/build/web/\n"
                f"  !frontend/build/web.tar.gz"
            )

    def test_dockerfile_copy_sources_not_excluded(self):
        """Dockerfile.cn 中所有 COPY 源都不能被 .dockerignore 排除（通用一致性）。"""
        dockerignore = PROJECT_ROOT / ".dockerignore"
        dockerfile = PROJECT_ROOT / "Dockerfile.cn"
        if not dockerignore.exists() or not dockerfile.exists():
            pytest.skip(".dockerignore 或 Dockerfile.cn 不存在")

        rules = [
            line.strip() for line in dockerignore.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.strip().startswith("#")
        ]

        copy_sources = []
        for line in dockerfile.read_text(encoding="utf-8").splitlines():
            m = re.match(r"\s*COPY\s+(\S+)", line)
            if m and not m.group(1).startswith("--"):
                copy_sources.append(m.group(1))

        assert copy_sources, "Dockerfile.cn 中未找到 COPY 指令"

        for src in copy_sources:
            excluded = self._is_excluded(rules, src)
            assert not excluded, (
                f"Dockerfile.cn 的 COPY 源 '{src}' 被 .dockerignore 排除了！\n"
                f"这会导致 docker build 失败（not found）→ CI 假绿 → 部署 502。\n"
                f"修复方法：调整 .dockerignore 规则，保留构建产物。"
            )


class TestCIDeploymentNoFalseGreen:
    """验证 CI 部署相关 job 失败时真实失败（不能假绿）。

    复现 bug：.backend_setup 的 before_script 设置了 set +e，docker build
    失败后脚本继续执行；deploy job 的健康检查失败也只打印警告。两者都
    导致 Job 显示 success，坏部署静默上线，用户访问才看到 502。
    """

    def test_build_images_docker_build_has_failure_check(self):
        """build_images 的 docker build 必须带失败检测（|| exit 1）。"""
        if not CI_FILE.exists():
            pytest.skip(f"文件不存在: {CI_FILE}")

        content = CI_FILE.read_text(encoding="utf-8")

        # 提取所有 docker build / $DOCKER build 命令（跳过注释行——
        # 注释里也可能出现 "docker build" 字样，如本测试的说明文字）。
        # 命令可能用 \ 续行（失败检测 || exit 1 在续行末尾），需拼接。
        raw_lines = content.splitlines()
        build_cmds = []
        for i, line in enumerate(raw_lines):
            stripped = line.strip()
            if stripped.startswith("#"):
                continue  # YAML 注释
            # 从行首匹配实际命令（echo 等文本里提到 docker build 的不算）
            if re.match(
                r'(?:- )?(?:\$DOCKER|docker)\s+build\b', stripped, re.IGNORECASE
            ):
                full = stripped
                j = i
                while full.rstrip().endswith("\\") and j + 1 < len(raw_lines):
                    j += 1
                    full += "\n" + raw_lines[j].strip()
                build_cmds.append(full)

        assert build_cmds, ".gitlab-ci.yml 中未找到 docker build 命令"

        for cmd in build_cmds:
            assert "exit 1" in cmd, (
                f"docker build 命令缺少失败检测（|| ... exit 1）：\n"
                f"  {cmd.strip()}\n\n"
                f".backend_setup 的 before_script 设置了 set +e，docker build 失败\n"
                f"不会自动中断脚本。若不加 || exit 1，构建失败会被吞掉，\n"
                f"deploy job 会静默使用 NAS 上残留的旧镜像部署（假绿 → 502）。\n"
                f"修复：在 docker build 命令后加 || {{ echo '构建失败'; exit 1; }}"
            )

    def test_deploy_healthcheck_failure_fails_job(self):
        """deploy_to_synology 健康检查未通过时必须 exit 1（不能只警告）。"""
        if not CI_FILE.exists():
            pytest.skip(f"文件不存在: {CI_FILE}")

        content = CI_FILE.read_text(encoding="utf-8")

        # 定位健康检查失败分支（警告文本）
        idx = content.find("HTTP 健康检查未通过")
        assert idx != -1, ".gitlab-ci.yml 中未找到健康检查失败分支"

        # 失败分支之后的 1500 字符内必须有 exit 1
        segment = content[idx : idx + 1500]
        assert "exit 1" in segment, (
            "deploy_to_synology 健康检查失败分支缺少 exit 1！\n"
            "之前失败时只打印警告，Job 仍显示 success，坏部署静默上线，\n"
            "用户访问页面才看到 502。\n"
            "修复：失败分支打印容器日志后加 exit 1，使 Job 真实失败。"
        )

    # ------------------------------------------------------------------
    # 复现测试：deploy 未设置 PUBLIC_BASE_URL，MCP OAuth 元数据指向本机
    # ------------------------------------------------------------------

    def test_deploy_sets_public_base_url_env(self):
        """复现 bug：docker run 未传 PUBLIC_BASE_URL，MCP OAuth 认证断裂。

        backend/app/core/config.py 中 PUBLIC_BASE_URL 默认值是
        http://127.0.0.1:8000。部署时不显式设置该环境变量时：

        1. MCP 服务器（app/mcp/server.py）用 PUBLIC_BASE_URL 构造
           issuer_url 和 resource_server_url；
        2. Claude Code POST /mcp 收到 401 后，按 WWW-Authenticate 头
           中的 resource_metadata 地址去发现 OAuth 端点 —— 实测返回：
             resource_metadata="http://127.0.0.1:8000/.well-known/oauth-protected-resource/mcp"
           指向的是客户端本机（127.0.0.1），完全不可达；
        3. 即使可达，OAuth 元数据里的 token_endpoint/issuer 也是
           127.0.0.1:8000，认证流程必然失败。

        修复：docker run 时通过 -e PUBLIC_BASE_URL=https://<对外域名>:<端口>
        覆盖默认值，使 MCP 服务器返回公网可达的 OAuth 端点。
        """
        if not CI_FILE.exists():
            pytest.skip(f"文件不存在: {CI_FILE}")

        content = CI_FILE.read_text(encoding="utf-8")

        # 定位 docker run 命令（deploy job 中）
        run_match = re.search(r'\$DOCKER run -d.*?(?=\n\s*\w|\n\s*\$|\n\s*[#}]|$)', content, re.S)
        assert run_match, ".gitlab-ci.yml 中未找到 docker run 命令"
        run_cmd = run_match.group(0)

        # 必须显式设置 PUBLIC_BASE_URL（不能依赖默认 http://127.0.0.1:8000）
        assert re.search(r'-e\s+PUBLIC_BASE_URL=\S+', run_cmd), (
            "deploy_to_synology 的 docker run 缺少 `-e PUBLIC_BASE_URL=...` 环境变量！\n"
            f"当前 docker run 命令：\n{run_cmd}\n\n"
            f"config.py 中 PUBLIC_BASE_URL 默认值是 http://127.0.0.1:8000，\n"
            f"MCP 服务器 401 响应的 WWW-Authenticate 头会返回\n"
            f"resource_metadata=\"http://127.0.0.1:8000/.well-known/oauth-protected-resource/mcp\"，\n"
            f"指向客户端本机不可达地址，Claude Code 的 OAuth 认证流程必然失败。\n"
            f"修复：docker run 参数中加 `-e PUBLIC_BASE_URL=https://<对外域名>:<端口>`。"
        )

        # 值不能是 localhost/127.0.0.1 类地址（否则同样不可达）
        base_url_match = re.search(r'-e\s+PUBLIC_BASE_URL=(\S+)', run_cmd)
        if base_url_match:
            bad = base_url_match.group(1)
            assert not re.search(r'(127\.0\.0\.1|localhost|0\.0\.0\.0)', bad), (
                f"PUBLIC_BASE_URL 指向了本机地址（{bad}）！\n"
                f"Claude Code 在客户端机器上按此地址发现 OAuth 端点，\n"
                f"127.0.0.1 指向客户端本机，无法到达 MCP 服务器。"
            )


class TestVersionBumpAndBuildTime:
    """验证 build_web 阶段版本号自动 +1 + 构建时间注入，deploy 成功后提交。

    需求：
    - frontend:build_web 调用 ci/bump_version.py 对 pubspec.yaml 版本号 +1
    - build_web 通过 --dart-define=BUILD_TIME 注入构建时间（设置页展示）
    - version_info.txt 作为 artifact 传递给 deploy job（两个 job 在不同 runner）
    - deploy_to_synology 部署成功（健康检查通过）后才 git commit + push，
      失败时不得提交；commit 带 [skip ci] 防止流水线无限循环
    """

    def _job_script(self, data, job_name):
        """取 job 的完整 script 文本（列表项拼接）。"""
        job = data.get(job_name)
        assert job is not None, f"找不到 {job_name} job，配置可能已变更"
        script = job.get("script", [])
        if isinstance(script, str):
            return script
        return "\n".join(script)

    def test_build_web_invokes_bump_version_script(self):
        """build_web 必须调用 bump_version.py 脚本。"""
        if not CI_FILE.exists():
            pytest.skip(f"文件不存在: {CI_FILE}")

        data = yaml.safe_load(CI_FILE.read_text(encoding="utf-8"))
        script = self._job_script(data, "frontend:build_web")

        assert "bump_version.py" in script, (
            "frontend:build_web 未调用版本号递增脚本（ci/bump_version.py）。\n"
            "需求：build_web 阶段对 pubspec.yaml 版本号自动 +1。"
        )

    def test_build_web_injects_build_time_dart_define(self):
        """build_web 的 flutter build 必须带 --dart-define=BUILD_TIME。"""
        if not CI_FILE.exists():
            pytest.skip(f"文件不存在: {CI_FILE}")

        data = yaml.safe_load(CI_FILE.read_text(encoding="utf-8"))
        script = self._job_script(data, "frontend:build_web")

        assert "--dart-define=BUILD_TIME" in script, (
            "frontend:build_web 的 flutter build 缺少 --dart-define=BUILD_TIME。\n"
            "需求：构建时间在 build_web 阶段注入，设置页面展示。"
        )

    def test_build_web_artifacts_include_version_info(self):
        """build_web 的 artifacts 必须包含 version_info.txt（传给 deploy job）。"""
        if not CI_FILE.exists():
            pytest.skip(f"文件不存在: {CI_FILE}")

        data = yaml.safe_load(CI_FILE.read_text(encoding="utf-8"))
        artifacts = data["frontend:build_web"].get("artifacts", {})
        paths = artifacts.get("paths", [])

        assert "frontend/version_info.txt" in paths, (
            "frontend:build_web 的 artifacts 缺少 frontend/version_info.txt。\n"
            "build_web（code01）与 deploy_to_synology（NAS）不在同一 runner，\n"
            "新版本号必须通过 artifact 传递。"
        )

    def test_deploy_pushes_version_only_after_success(self):
        """git push 必须位于部署成功分支（健康检查通过）内，失败时不提交。"""
        if not CI_FILE.exists():
            pytest.skip(f"文件不存在: {CI_FILE}")

        content = CI_FILE.read_text(encoding="utf-8")

        success_marker = "部署成功！容器内健康检查通过"
        fail_marker = "错误：部署验证失败"
        push_marker = "git push"

        assert success_marker in content, "找不到部署成功分支标记"
        assert push_marker in content, "deploy job 中找不到 git push 命令"

        success_idx = content.find(success_marker)
        push_idx = content.find(push_marker)
        fail_idx = content.find(fail_marker)

        assert push_idx > success_idx, (
            f"git push（位置 {push_idx}）必须位于部署成功分支\n"
            f"（“{success_marker}”，位置 {success_idx}）之后。\n"
            "需求：只有 deploy_to_synology 成功运行时才提交到 git 远程仓库。"
        )
        if fail_idx != -1:
            assert push_idx < fail_idx, (
                "git push 位于部署失败分支（“错误：部署验证失败”）之后，\n"
                "失败时会错误提交！应放在成功分支内。"
            )

    def test_deploy_push_uses_ci_job_token(self):
        """git push 必须使用 CI_JOB_TOKEN 凭据（无额外 PAT 配置）。"""
        if not CI_FILE.exists():
            pytest.skip(f"文件不存在: {CI_FILE}")

        content = CI_FILE.read_text(encoding="utf-8")

        assert "gitlab-ci-token:${CI_JOB_TOKEN}" in content, (
            "git push 的 URL 必须使用 CI_JOB_TOKEN 凭据：\n"
            "  https://gitlab-ci-token:${CI_JOB_TOKEN}@home.chenkaidi.top:509/...\n"
            "若 GitLab 15.9+ 默认只读导致 push 被拒，需在项目设置放开\n"
            "CI_JOB_TOKEN 写权限或改用 PAT（见日志指引）。"
        )

    def test_deploy_commit_has_skip_ci(self):
        """版本号提交必须带 [skip ci]，防止 push 触发无限流水线循环。"""
        if not CI_FILE.exists():
            pytest.skip(f"文件不存在: {CI_FILE}")

        content = CI_FILE.read_text(encoding="utf-8")

        assert "[skip ci]" in content, (
            "deploy 的 git commit message 必须包含 [skip ci]。\n"
            "否则 push 版本号提交会触发新流水线 → 又 +1 → 又 push，无限循环。"
        )

