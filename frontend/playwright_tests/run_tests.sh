#!/usr/bin/env bash
# Playwright E2E 测试本地运行脚本（issue #39）
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---- 默认参数 ----
BASE_URL="${TEST_BASE_URL:-http://localhost:9000}"
HEADLESS="${TEST_HEADLESS:-true}"
TEST_TARGET="${1:-tests/}"
PYTEST_ARGS=()
BUILD_WEB="false"
NO_MOCK="false"
MOCK_PID=""

# ---- 清理 mock backend ----
_cleanup() {
    if [ -n "$MOCK_PID" ] && kill -0 "$MOCK_PID" 2>/dev/null; then
        echo ""
        echo "[cleanup] 停止 mock backend (PID $MOCK_PID)..."
        kill "$MOCK_PID" 2>/dev/null
        wait "$MOCK_PID" 2>/dev/null || true
    fi
}
trap _cleanup EXIT

# ---- 解析命令行参数 ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-url=*) BASE_URL="${1#*=}"; shift ;;
        --base-url)   BASE_URL="$2"; shift 2 ;;
        --headed)     HEADLESS="false"; shift ;;
        --debug)      HEADLESS="false"; DEBUG="true"; shift ;;
        --build-web)  BUILD_WEB="true"; shift ;;
        --no-mock)    NO_MOCK="true"; shift ;;
        --html)       PYTEST_ARGS+=("--html=report.html" "--self-contained-html"); shift ;;
        -k)           PYTEST_ARGS+=("-k" "$2"); shift 2 ;;
        -v)           PYTEST_ARGS+=("-v"); shift ;;
        -s)           PYTEST_ARGS+=("-s"); shift ;;
        -h|--help)
            echo "用法: ./run_tests.sh [选项] [测试文件/目录]"
            echo ""
            echo "选项:"
            echo "  --base-url=URL    目标服务器地址 (默认: http://localhost:9000)"
            echo "  --headed          显示浏览器窗口"
            echo "  --debug           调试模式：显示浏览器 + 操作间停顿"
            echo "  --build-web       重新构建 Flutter Web"
            echo "  --no-mock         不自动启动 mock backend（使用外部服务器）"
            echo "  --html            生成 HTML 报告"
            echo "  -k EXPR           按关键字筛选测试"
            echo "  -v                详细输出"
            echo "  -s                显示 print 输出"
            echo ""
            echo "环境变量:"
            echo "  TEST_BASE_URL     目标服务器地址"
            echo "  TEST_HEADLESS     是否无头模式 (true/false)"
            echo "  TEST_USERNAME     Portainer 用户名 (默认: admin)"
            echo "  TEST_PASSWORD     Portainer 密码 (默认: password)"
            echo "  TEST_CHANNEL      Playwright channel（如 chrome，使用系统 Chrome）"
            echo "  CHROMIUM_EXECUTABLE  指定浏览器二进制"
            echo ""
            echo "示例:"
            echo "  ./run_tests.sh                            # 默认：启动 mock + 运行测试"
            echo "  ./run_tests.sh --build-web                # 重新构建 Web 后运行"
            echo "  ./run_tests.sh --no-mock --base-url=http://prod:8082  # 使用外部服务器"
            echo "  ./run_tests.sh --headed --html             # 有头模式 + HTML 报告"
            exit 0
            ;;
        *)  TEST_TARGET="$1"; shift ;;
    esac
done

# ---- 构建 Flutter Web（如需要） ----
FLUTTER_BUILD_DIR="$PROJECT_DIR/build/web"

if [ "$NO_MOCK" = "false" ]; then
    if [ "$BUILD_WEB" = "true" ] || [ ! -f "$FLUTTER_BUILD_DIR/index.html" ]; then
        echo "[build] 构建 Flutter Web..."
        cd "$PROJECT_DIR"
        # 与 selenium_tests 保持一致：--no-tree-shake-icons + --wasm
        export LD_LIBRARY_PATH="$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")/bin/cache/dart-sdk/bin/utils:${LD_LIBRARY_PATH:-}"
        flutter build web --wasm --base-href / --release --no-tree-shake-icons
        cd "$SCRIPT_DIR"
    else
        echo "[build] Flutter Web 已存在，跳过构建（使用 --build-web 强制重新构建）"
    fi
fi

# ---- 创建/检查虚拟环境 ----
if [ ! -d "venv" ]; then
    echo "[setup] 创建虚拟环境..."
    python3 -m venv venv
fi

echo "[setup] 激活虚拟环境..."
source venv/bin/activate

# ---- 安装依赖 ----
if ! python -c "import playwright, pytest" 2>/dev/null; then
    echo "[setup] 安装依赖..."
    pip install -r requirements.txt -q
fi

echo "[setup] 依赖 OK"

# ---- 检查 playwright 浏览器 ----
if ! python -c "from playwright.sync_api import sync_playwright; p=sync_playwright().start(); p.chromium.launch(headless=True).close(); p.stop()" 2>/dev/null; then
    echo "[setup] 安装 playwright 浏览器（chromium）..."
    python -m playwright install chromium
fi

# ---- 启动 mock backend ----
if [ "$NO_MOCK" = "false" ]; then
    echo ""
    echo "[mock] 启动 mock backend..."
    MOCK_PORT="${BASE_URL##*:}"
    # mock_backend 复用 selenium_tests 的版本（提供 Flutter Web 静态文件 + API mock）
    export MOCK_BACKEND_PORT="$MOCK_PORT"
    python ../selenium_tests/mock_backend.py &
    MOCK_PID=$!
    echo "[mock] mock backend PID: $MOCK_PID，端口: $MOCK_PORT"

    # 等待 mock backend 就绪
    echo -n "[mock] 等待就绪"
    for i in $(seq 1 30); do
        if python -c "
import urllib.request
try:
    urllib.request.urlopen('http://localhost:$MOCK_PORT/info', timeout=2)
    exit(0)
except Exception:
    exit(1)
" 2>/dev/null; then
            echo " ✓"
            break
        fi
        echo -n "."
        sleep 1
    done
    echo ""

    export MOCK_BACKEND_URL="http://localhost:$MOCK_PORT"
else
    echo "[mock] 跳过 mock backend 启动（--no-mock）"
    export MOCK_BACKEND_URL="${MOCK_BACKEND_URL:-$BASE_URL}"
fi

# ---- 运行测试 ----
# 避免本地代理干扰浏览器通信
export NO_PROXY="localhost,127.0.0.1,::1"
export no_proxy="$NO_PROXY"
export TEST_BASE_URL="$BASE_URL"
export TEST_HEADLESS="$HEADLESS"
export TEST_USERNAME="${TEST_USERNAME:-admin}"
export TEST_PASSWORD="${TEST_PASSWORD:-password}"
export TEST_DEBUG="${DEBUG:-false}"

echo ""
echo "=============================="
echo "  目标: $BASE_URL"
echo "  Mock:  $MOCK_BACKEND_URL"
echo "  Headless: $HEADLESS"
echo "  测试: $TEST_TARGET"
echo "=============================="
echo ""

pytest $TEST_TARGET -v "${PYTEST_ARGS[@]}"
