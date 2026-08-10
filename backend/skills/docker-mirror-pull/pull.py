#!/usr/bin/env python3
"""Docker 镜像拉取工具（单次尝试，使用 sudo）

用法: python3 pull.py <完整镜像名> [原始镜像名]
示例: python3 pull.py docker.1ms.run/langgenius/dify-plugin-daemon:0.6.3-local langgenius/dify-plugin-daemon:0.6.3-local

使用 sudo docker 拉取，镜像存入系统级 Docker daemon，所有用户共享。
该脚本执行单次 docker pull，返回退出码表示成功/失败。
由外层 AI 控制镜像源切换逻辑。
"""

import subprocess
import sys
import time

# 统一使用 sudo docker，确保镜像对所有用户可用
DOCKER_CMD = ["sudo", "docker"]


def check_sudo():
    """检查 sudo 权限是否可用"""
    try:
        result = subprocess.run(
            ["sudo", "-n", "true"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        return result.returncode == 0
    except Exception:
        return False


def pull_image(full_image: str) -> int:
    """拉取指定镜像，返回 docker pull 的退出码"""
    print(f"\n{'='*60}")
    print(f"sudo docker pull {full_image}")
    print(f"{'='*60}")

    start = time.time()
    try:
        result = subprocess.run(
            [*DOCKER_CMD, "pull", full_image],
            capture_output=False,
            text=True,
            timeout=600,
        )
        elapsed = time.time() - start
        if result.returncode == 0:
            print(f"\n✓ 拉取成功 ({elapsed:.1f}s): {full_image}")
            return 0
        else:
            print(f"\n✗ 拉取失败 ({elapsed:.1f}s), 返回码: {result.returncode}")
            return result.returncode
    except subprocess.TimeoutExpired:
        print(f"\n✗ 拉取超时 (>{600}s): {full_image}")
        return 124
    except FileNotFoundError:
        print("\n✗ 未找到 docker 或 sudo 命令，请确认 Docker 已安装并在 PATH 中")
        sys.exit(127)
    except KeyboardInterrupt:
        print("\n中断: 用户取消操作")
        sys.exit(130)


def tag_image(mirror_prefix: str, original_image: str):
    """拉取成功后打上原始标签"""
    full_image = f"{mirror_prefix}/{original_image}"
    try:
        subprocess.run(
            [*DOCKER_CMD, "tag", full_image, original_image],
            capture_output=True,
            text=True,
            timeout=30,
            check=True,
        )
        print(f"✓ 已打标签: {original_image}")
    except subprocess.CalledProcessError as e:
        print(f"⚠ 打标签失败: {e.stderr}")


def main():
    if len(sys.argv) < 2:
        print("用法: python3 pull.py <完整镜像名> [原始镜像名]")
        print("示例: python3 pull.py docker.1ms.run/library/nginx:latest nginx:latest")
        print()
        print("参数:")
        print("  完整镜像名   带镜像源前缀的完整镜像地址（必填）")
        print("  原始镜像名   拉取成功后额外打的标签（可选）")
        print()
        print("注意: 使用 sudo docker，可能需要输入密码")
        sys.exit(1)

    full_image = sys.argv[1]
    original_image = sys.argv[2] if len(sys.argv) > 2 else None

    # 检查 sudo 权限
    if not check_sudo():
        print("⚠ 未检测到免密 sudo 权限，拉取过程中可能需要输入密码")

    exit_code = pull_image(full_image)

    if exit_code == 0 and original_image:
        prefix = full_image[: full_image.index("/")] if "/" in full_image else ""
        tag_image(prefix, original_image)

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
