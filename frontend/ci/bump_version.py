#!/usr/bin/env python3
"""版本号自动 +1 脚本（CI 中 frontend:build_web 阶段调用）。

将 pubspec.yaml 的 `version: X.Y.Z+N` 递增为 `X.Y.(Z+1).(N+1)`
（patch 版本 +1 且 build number +1），写回 pubspec.yaml，
并把新版本号输出到 stdout。

用法:
    python3 ci/bump_version.py [--pubspec <path>] [--output <file>]

    --pubspec   pubspec.yaml 路径（默认: 脚本同级的 ../pubspec.yaml）
    --output    把新版本号写入指定文件（CI 生成 version_info.txt artifact 用）

退出码:
    0   成功
    1   pubspec.yaml 不存在 / version 行缺失 / 格式非法 / 输出目录不存在。
        校验失败时不修改 pubspec.yaml（不静默使用旧版本）。
"""

import argparse
import re
import sys
from pathlib import Path

VERSION_RE = re.compile(r"^version:\s*(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?\s*$")


def load_version(pubspec: Path) -> tuple[int, int, int, int]:
    """读取 version 行，返回 (major, minor, patch, build)。"""
    if not pubspec.exists():
        raise ValueError(f"pubspec.yaml 不存在: {pubspec}")
    for line in pubspec.read_text(encoding="utf-8").splitlines():
        m = VERSION_RE.match(line.strip())
        if m:
            major, minor, patch, build = m.groups()
            return int(major), int(minor), int(patch), int(build) if build else 0
    raise ValueError(
        f"pubspec.yaml 中未找到合法的 version 行（期望 X.Y.Z 或 X.Y.Z+N）: {pubspec}"
    )


def bump(version: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    """patch 版本 +1 且 build number +1。"""
    major, minor, patch, build = version
    return major, minor, patch + 1, build + 1


def main() -> int:
    default_pubspec = Path(__file__).resolve().parent.parent / "pubspec.yaml"
    parser = argparse.ArgumentParser(description="pubspec.yaml 版本号自动 +1")
    parser.add_argument("--pubspec", type=Path, default=default_pubspec,
                        help=f"pubspec.yaml 路径（默认: {default_pubspec}）")
    parser.add_argument("--output", type=Path, default=None,
                        help="新版本号写入该文件（生成 version_info.txt）")
    args = parser.parse_args()

    # 前置校验全部通过后才允许写文件（校验失败不改动任何内容）
    if args.output is not None and not args.output.parent.exists():
        print(f"错误: 输出目录不存在: {args.output.parent}", file=sys.stderr)
        return 1

    try:
        old = load_version(args.pubspec)
    except ValueError as e:
        print(f"错误: {e}", file=sys.stderr)
        return 1

    new = bump(old)
    new_version = f"{new[0]}.{new[1]}.{new[2]}+{new[3]}"

    # 写回 pubspec.yaml（只替换第一处 version 行，保留其余格式）
    lines = args.pubspec.read_text(encoding="utf-8").splitlines()
    replaced = False
    out_lines = []
    for line in lines:
        if VERSION_RE.match(line.strip()) and not replaced:
            out_lines.append(f"version: {new_version}")
            replaced = True
        else:
            out_lines.append(line)
    args.pubspec.write_text("\n".join(out_lines) + "\n", encoding="utf-8")

    # stdout 输出新版本号（CI 直接捕获）
    print(new_version)

    # --output 写入新版本号（CI 生成 version_info.txt artifact 传递到 deploy job）
    if args.output is not None:
        try:
            args.output.write_text(new_version + "\n", encoding="utf-8")
        except OSError as e:
            print(f"错误: 写入输出文件失败 {args.output}: {e}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
