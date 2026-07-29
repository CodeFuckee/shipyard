#!/usr/bin/env bash
# ================================================================
# Flutter SDK 自动检测脚本（macOS / Linux）
# ================================================================
if command -v flutter >/dev/null 2>&1; then
  echo "Flutter found in PATH: $(which flutter)"
  exit 0
fi
for p in "$FLUTTER_ROOT" "$HOME/flutter" "/usr/local/flutter" "/opt/flutter" "$HOME/fvm/default"; do
  if [ -n "$p" ] && [ -f "$p/bin/flutter" ]; then
    export PATH="$p/bin:$PATH"
    echo "Flutter found at: $p"
    exit 0
  fi
done
echo "WARNING: Flutter not found. Set FLUTTER_ROOT in GitLab Variables or add flutter to PATH."
