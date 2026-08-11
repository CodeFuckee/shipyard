"""镜像拉取执行器 — 通过 Docker daemon 执行拉取与打标签。

生产实现（DockerSocketPuller）使用 docker SDK 连接 Docker Unix socket
（DOCKER_SOCKET_PATH，容器部署时已挂载），不依赖 sudo / docker CLI；
测试场景替换为 FakePuller（见 tests/test_agent_tools.py）。

约定：所有方法返回 (exit_code, message)，exit_code 0 = 成功，
与 backend/skills/docker-mirror-pull/pull.py 的退出码语义保持一致。
"""

import concurrent.futures

import docker

from app.core.config import AGENT_PULL_TIMEOUT, DOCKER_SOCKET_PATH


class ImagePuller:
    """拉取执行器接口。"""

    def pull(self, full_image: str, original_image: str | None = None) -> tuple[int, str]:
        """拉取 full_image，成功后可选打上 original_image 标签。"""
        raise NotImplementedError

    def tag(self, full_image: str, original_image: str) -> tuple[int, str]:
        """给已存在的镜像打标签。"""
        raise NotImplementedError


class DockerSocketPuller(ImagePuller):
    """生产执行器：docker SDK 连接 Docker Unix socket。"""

    def __init__(self, base_url: str | None = None, timeout: int = AGENT_PULL_TIMEOUT):
        self.base_url = base_url or f"unix://{DOCKER_SOCKET_PATH}"
        self.timeout = timeout

    def _client(self) -> docker.DockerClient:
        return docker.DockerClient(base_url=self.base_url)

    def pull(self, full_image: str, original_image: str | None = None) -> tuple[int, str]:
        # docker SDK 的 images.pull 无超时参数，用线程池加超时保护
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            future = pool.submit(self._do_pull, full_image, original_image)
            try:
                return future.result(timeout=self.timeout)
            except concurrent.futures.TimeoutError:
                return 124, f"拉取超时（>{self.timeout} 秒）: {full_image}"
            except Exception as exc:
                return 2, f"拉取异常: {exc}"

    def _do_pull(self, full_image: str, original_image: str | None) -> tuple[int, str]:
        client = self._client()
        try:
            try:
                client.images.pull(full_image)
            except docker.errors.NotFound as exc:
                return 1, f"镜像不存在或不可访问: {exc}"
            except docker.errors.APIError as exc:
                return 1, f"拉取失败: {exc}"
            except Exception as exc:
                return 2, f"拉取异常: {exc}"

            message = f"拉取成功: {full_image}"
            if original_image and original_image != full_image:
                code, tag_message = self.tag(full_image, original_image)
                message += f"；{tag_message}"
            return 0, message
        finally:
            client.close()

    def tag(self, full_image: str, original_image: str) -> tuple[int, str]:
        client = self._client()
        try:
            image = client.images.get(full_image)
            image.tag(original_image)
            return 0, f"已打标签 {original_image}"
        except docker.errors.ImageNotFound:
            return 1, f"打标签失败: 镜像不存在 {full_image}"
        except Exception as exc:
            return 1, f"打标签失败: {exc}"
        finally:
            client.close()
