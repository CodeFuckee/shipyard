#!/usr/bin/env bash
# ================================================================
# Flutter HAR 构建设置脚本（macOS / Linux）
# 如果 HarmonyOS SDK 不可用，优雅退出而非报错。
# ================================================================

echo "=== HAR Build Setup (Unix) ==="

if [ -n "$FLUTTER_ROOT" ] && [ -d "$FLUTTER_ROOT/bin" ]; then
  export PATH="$FLUTTER_ROOT/bin:$PATH"
fi

export HVIGOR_USER_HOME="${HVIGOR_USER_HOME:-/tmp/hvigor_home}"
mkdir -p "$HVIGOR_USER_HOME"

echo "HVIGOR_USER_HOME = $HVIGOR_USER_HOME"
echo "PUB_HOSTED_URL = ${PUB_HOSTED_URL:-not set}"
echo "FLUTTER_STORAGE_BASE_URL = ${FLUTTER_STORAGE_BASE_URL:-not set}"

if command -v node > /dev/null 2>&1; then
  echo "Node.js: $(node --version)"
else
  echo "WARNING: Node.js not found. HAR build may fail."
fi

git config --global --add safe.directory "$CI_PROJECT_DIR" 2>/dev/null || true

echo "=== Running flutter pub get ==="
flutter pub get

echo "=== Running flutter build har --release ==="
if flutter build har --release; then
  echo "=== HAR build succeeded ==="
else
  echo "=== HAR build skipped (HarmonyOS SDK not available on this platform) ==="
fi
