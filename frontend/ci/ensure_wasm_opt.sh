#!/usr/bin/env bash
# ============================================================
# ensure_wasm_opt.sh —— 确保 dart2wasm 工具链中存在 wasm-opt（binaryen）
#
# ⚠️ baseline 版本：仅支持 Linux amd64；安装失败时不会报错退出
# （"假成功"），已知 bug，待修复。此脚本由 .gitlab-ci.yml 的
# frontend:build_web 调用，用于补齐 ohos 分支 Flutter SDK 缺失的
# wasm-opt（binaryen >= 116，支持 --closed-world 参数）。
# ============================================================
set -u

# 目标目录：flutter SDK 的 dart-sdk/bin/utils（测试可注入覆盖）
UTILS_DIR="${WASM_OPT_UTILS_DIR:-}"
if [ -z "${UTILS_DIR}" ]; then
  FLUTTER_BIN_PATH=$(readlink -f "$(command -v flutter)")
  UTILS_DIR="$(dirname "$(dirname "$FLUTTER_BIN_PATH")")/bin/cache/dart-sdk/bin/utils"
fi
echo "DART_SDK_UTILS=${UTILS_DIR}"

if [ ! -x "${UTILS_DIR}/wasm-opt" ]; then
  echo "⬇️ 安装 wasm-opt（binaryen 120，Debian sid）"
  mkdir -p "${UTILS_DIR}"
  if [ -n "${WASM_OPT_INSTALL_CMD:-}" ]; then
    # 测试注入的安装命令（跳过真实下载）
    bash -c "${WASM_OPT_INSTALL_CMD}"
  else
    cd /tmp
    curl -fsSL --connect-timeout 30 -o binaryen_120.deb \
      "http://ftp.debian.org/debian/pool/main/b/binaryen/binaryen_120-4_amd64.deb" \
      || curl -fsSL --connect-timeout 30 -o binaryen_120.deb \
      "https://mirrors.tuna.tsinghua.edu.cn/debian/pool/main/b/binaryen/binaryen_120-4_amd64.deb"
    rm -rf /tmp/binaryen120 && dpkg -x binaryen_120.deb /tmp/binaryen120
    cp /tmp/binaryen120/usr/bin/wasm-opt "${UTILS_DIR}/"
    cp /tmp/binaryen120/usr/lib/x86_64-linux-gnu/libbinaryen.so "${UTILS_DIR}/"
  fi
  echo "✓ wasm-opt 已安装: $(${UTILS_DIR}/wasm-opt --version)"
else
  echo "✓ wasm-opt 已存在，跳过安装"
fi

# wasm-opt 依赖 libbinaryen.so，通过 LD_LIBRARY_PATH 提供
# （dart compile wasm 子进程会继承）
export LD_LIBRARY_PATH="${UTILS_DIR}:${LD_LIBRARY_PATH:-}"
