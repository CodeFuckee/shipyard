#!/bin/bash
# 国内版 Web 前端构建脚本
# 用法: bash build-web-cn.sh
# 前置条件: 已安装 Flutter SDK

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRONTEND_DIR="../../FlutterProjects/mobile_portainer_flutter_module"
OUTPUT_DIR="$SCRIPT_DIR/web-build"

echo "=== 编译 Flutter Web ==="
cd "$FRONTEND_DIR"
flutter pub get
flutter build web --base-href / --release

echo "=== 复制构建产物到 $OUTPUT_DIR ==="
rm -rf "$OUTPUT_DIR"
cp -r build/web "$OUTPUT_DIR"
echo "=== 完成 ==="
