#!/usr/bin/env python3
"""从 Dockerfile 和 docker-compose.yml 中提取 Docker 镜像列表

用法: python3 extract_images.py <文件路径> [--no-json]

支持解析:
  - Dockerfile (FROM 指令)
  - docker-compose.yml / docker-compose.yaml (services.*.image)

输出 JSON 格式，每项包含 image, type, source_line。
--no-json 输出人类可读格式。
"""

import json
import re
import sys
from pathlib import Path

# 不需要拉取的镜像
SKIP_IMAGES = {"scratch", ""}


def parse_dockerfile(content: str) -> list[dict]:
    """从 Dockerfile 内容中提取所有 FROM 镜像"""
    images = []
    arg_values: dict[str, str] = {}

    # 第一遍：收集所有 ARG 定义
    for line in content.splitlines():
        stripped = line.strip()
        # 跳过注释和空行
        if not stripped or stripped.startswith("#"):
            continue

        # ARG VARIABLE=default_value 或 ARG VARIABLE
        arg_match = re.match(r"ARG\s+(\w+)(?:=(.+))?", stripped, re.IGNORECASE)
        if arg_match:
            var_name = arg_match.group(1)
            default = arg_match.group(2) or ""
            if var_name not in arg_values:
                arg_values[var_name] = default

    # 第二遍：提取 FROM 指令
    for line in content.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        # 匹配 FROM 指令
        # FROM [--platform=xxx] <image>[:<tag>] [AS <name>]
        # FROM <image>[@<digest>] [AS <name>]
        from_match = re.match(
            r"FROM\s+(?:--\S+\s+)?(\S+)",
            stripped,
            re.IGNORECASE,
        )
        if not from_match:
            continue

        raw_image = from_match.group(1)

        # 去掉 AS 别名
        raw_image = re.sub(r"\s+AS\s+.+$", "", raw_image, flags=re.IGNORECASE).strip()

        # 跳过 scratch
        if raw_image.lower() == "scratch":
            continue

        # 处理变量引用 ${VAR} 或 $VAR
        var_refs = re.findall(r"\$\{?(\w+)\}?", raw_image)
        is_variable = False
        resolved_image = raw_image

        for var in var_refs:
            if var in arg_values and arg_values[var]:
                resolved_image = resolved_image.replace(
                    f"${{{var}}}", arg_values[var]
                ).replace(f"${var}", arg_values[var])
            else:
                is_variable = True

        images.append({
            "image": resolved_image if not is_variable else raw_image,
            "type": "variable" if is_variable else "fixed",
            "source_line": stripped.strip(),
        })

    return images


def parse_docker_compose(content: str) -> list[dict]:
    """从 docker-compose.yml 内容中提取所有 image 字段"""
    images = []

    # 简单逐行解析，找到 services: 块下的 image: 字段
    in_services = False
    current_service_has_build = False
    current_service_has_image = False
    indent_level = 0

    for line in content.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        # 检测缩进层级
        current_indent = len(line) - len(line.lstrip())

        # services: 顶级键
        if re.match(r"^services:\s*$", stripped):
            in_services = True
            indent_level = current_indent
            continue

        # 另一个顶级键，退出 services 块
        if in_services and current_indent <= indent_level and stripped.endswith(":") and not stripped.startswith("-"):
            # 检查是否是 services 下的服务名
            pass

        if in_services and current_indent > indent_level:
            # 服务定义级别（缩进 2 空格）
            if current_indent == indent_level + 2 and not stripped.startswith("-"):
                # 新服务开始
                current_service_has_build = False
                current_service_has_image = False

            # image: xxx
            if re.match(r"^image:\s*\S", stripped):
                image_match = re.match(r"^image:\s*(.+)$", stripped)
                if image_match:
                    image_value = image_match.group(1).strip().strip('"').strip("'")
                    current_service_has_image = True

                    # 检测变量引用
                    has_var = bool(re.search(r"\$\{?\w+\}?", image_value))
                    images.append({
                        "image": image_value,
                        "type": "variable" if has_var else "fixed",
                        "source_line": stripped.strip(),
                    })

            # build: xxx (标记当前服务有 build)
            if re.match(r"^build:\s*", stripped):
                current_service_has_build = True

    # 过滤：如果服务只有 build 没有 image，对应的 image 不算
    # 注：简单解析无法精确匹配，这里返回所有 image，由 AI 做进一步判断
    return images


def extract_from_file(filepath: str) -> list[dict]:
    """根据文件类型自动选择解析器"""
    path = Path(filepath)
    if not path.exists():
        print(f"错误: 文件不存在: {filepath}", file=sys.stderr)
        sys.exit(1)

    content = path.read_text(encoding="utf-8")
    filename = path.name.lower()

    if filename == "dockerfile" or filename.startswith("dockerfile."):
        return parse_dockerfile(content)
    elif filename in ("docker-compose.yml", "docker-compose.yaml") or "docker-compose" in filename:
        return parse_docker_compose(content)
    else:
        # 尝试自动检测
        if content.strip().startswith("{") or content.strip().startswith("["):
            print(f"警告: {filepath} 看起来是 JSON 文件，不是 Dockerfile 或 docker-compose.yml", file=sys.stderr)
            sys.exit(1)

        # 根据内容特征判断
        if re.search(r"^\s*FROM\s+", content, re.MULTILINE | re.IGNORECASE):
            return parse_dockerfile(content)
        elif re.search(r"^\s*services\s*:", content, re.MULTILINE):
            return parse_docker_compose(content)
        else:
            print(f"错误: 无法识别文件类型: {filepath}", file=sys.stderr)
            print("支持: Dockerfile (含 FROM 指令) 或 docker-compose.yml (含 services 块)", file=sys.stderr)
            sys.exit(1)


def main():
    if len(sys.argv) < 2:
        print("用法: python3 extract_images.py <文件路径> [--no-json]", file=sys.stderr)
        print("示例: python3 extract_images.py Dockerfile", file=sys.stderr)
        print("示例: python3 extract_images.py docker-compose.yml", file=sys.stderr)
        sys.exit(1)

    filepath = sys.argv[1]
    use_json = "--no-json" not in sys.argv

    images = extract_from_file(filepath)

    if use_json:
        print(json.dumps(images, ensure_ascii=False, indent=2))
    else:
        if not images:
            print(f"未从 {filepath} 中提取到任何镜像")
            return

        fixed = [i for i in images if i["type"] == "fixed"]
        variable = [i for i in images if i["type"] == "variable"]

        print(f"从 {filepath} 提取到 {len(images)} 个镜像:\n")
        if fixed:
            print("📦 可直接拉取:")
            for item in fixed:
                print(f"  - {item['image']}")
                print(f"    ← {item['source_line']}")
        if variable:
            print("\n⚠️  含变量占位符（需确认）:")
            for item in variable:
                print(f"  - {item['image']}")
                print(f"    ← {item['source_line']}")


if __name__ == "__main__":
    main()
