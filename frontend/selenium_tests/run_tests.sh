#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---- 默认参数 ----
BASE_URL="${TEST_BASE_URL:-http://localhost:9000}"
BROWSER="${TEST_BROWSER:-chrome}"
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
        --browser=*)  BROWSER="${1#*=}"; shift ;;
        --browser)    BROWSER="$2"; shift 2 ;;
        --headed)     HEADLESS="false"; shift ;;
        --debug)      HEADLESS="false"; DEBUG="true"; shift ;;
        --smoke)      TEST_TARGET="tests/ -m smoke"; shift ;;
        --build-web)  BUILD_WEB="true"; shift ;;
        --no-mock)    NO_MOCK="true"; shift ;;
        -k)           PYTEST_ARGS+=("-k" "$2"); shift 2 ;;
        -v)           PYTEST_ARGS+=("-v"); shift ;;
        -s)           PYTEST_ARGS+=("-s"); shift ;;
        --html)       PYTEST_ARGS+=("--html=report.html" "--self-contained-html"); shift ;;
        -h|--help)
            echo "用法: ./run_tests.sh [选项] [测试文件/目录]"
            echo ""
            echo "选项:"
            echo "  --base-url=URL    目标服务器地址 (默认: http://localhost:9000)"
            echo "  --browser=NAME    浏览器: chrome | firefox (默认: chrome)"
            echo "  --headed          显示浏览器窗口"
            echo "  --debug           调试模式：显示浏览器 + 操作间停顿"
            echo "  --smoke           仅运行冒烟测试"
            echo "  --build-web       重新构建 Flutter Web"
            echo "  --no-mock         不自动启动 mock backend（使用外部服务器）"
            echo "  --html            生成 HTML 报告"
            echo "  -k EXPR           按关键字筛选测试"
            echo "  -v                详细输出"
            echo "  -s                显示 print 输出"
            echo ""
            echo "环境变量:"
            echo "  TEST_BASE_URL     目标服务器地址"
            echo "  TEST_BROWSER      浏览器类型"
            echo "  TEST_HEADLESS     是否无头模式 (true/false)"
            echo "  TEST_USERNAME     Portainer 用户名 (默认: admin)"
            echo "  TEST_PASSWORD     Portainer 密码 (默认: password)"
            echo "  TEST_DEBUG        调试模式 (true/false，默认: false)"
            echo ""
            echo "示例:"
            echo "  ./run_tests.sh                           # 默认：启动 mock + 运行测试"
            echo "  ./run_tests.sh --build-web               # 重新构建 Web 后运行"
            echo "  ./run_tests.sh --no-mock --base-url=http://prod:8082  # 使用外部服务器"
            echo "  ./run_tests.sh --headed --smoke          # 有头模式 + 冒烟测试"
            echo "  ./run_tests.sh --html -k nav_bar         # 生成报告 + 筛选"
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
        flutter build web --base-href / --release
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
if ! python -c "import selenium" 2>/dev/null; then
    echo "[setup] 安装依赖..."
    pip install -r requirements.txt -q
fi

echo "[setup] 依赖 OK"

# ---- ChromeDriver 版本检查 ----
_check_chromedriver_version() {
    # 仅检查 chrome 浏览器
    if [ "$BROWSER" != "chrome" ]; then
        return 0
    fi

    # 定位 chromedriver 路径
    local chromedriver=""
    if [ -n "$CHROMEDRIVER_PATH" ]; then
        chromedriver="$CHROMEDRIVER_PATH"
    elif command -v chromedriver &>/dev/null; then
        chromedriver="$(command -v chromedriver)"
    else
        # 尝试从 webdriver-manager 缓存查找
        chromedriver=$(python -c "
import os, glob
cache = os.path.expanduser('~/.wdm/drivers/chromedriver')
if os.path.isdir(cache):
    files = glob.glob(os.path.join(cache, '**', 'chromedriver'), recursive=True)
    if files:
        print(files[0])
" 2>/dev/null)
    fi

    if [ -z "$chromedriver" ] || [ ! -x "$chromedriver" ]; then
        echo "[chromedriver] 未找到 chromedriver，将由 webdriver-manager 自动下载"
        return 0
    fi

    # 获取 chromedriver 版本
    local cd_version
    cd_version=$("$chromedriver" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [ -z "$cd_version" ]; then
        echo "[chromedriver] 警告: 无法获取 chromedriver 版本"
        return 0
    fi
    local cd_major="${cd_version%%.*}"

    # 定位 Chrome/Chromium 浏览器
    local chrome_bin=""
    if [ -n "$CHROMIUM_BINARY" ] && [ -x "$CHROMIUM_BINARY" ]; then
        chrome_bin="$CHROMIUM_BINARY"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        chrome_bin="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    elif command -v google-chrome &>/dev/null; then
        chrome_bin="$(command -v google-chrome)"
    elif command -v chromium-browser &>/dev/null; then
        chrome_bin="$(command -v chromium-browser)"
    elif command -v chromium &>/dev/null; then
        chrome_bin="$(command -v chromium)"
    fi

    if [ -z "$chrome_bin" ] || [ ! -x "$chrome_bin" ]; then
        echo "[chromedriver] 警告: 未找到 Chrome/Chromium 浏览器，跳过版本检查"
        return 0
    fi

    # 获取 Chrome 版本
    local chrome_version
    chrome_version=$("$chrome_bin" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [ -z "$chrome_version" ]; then
        echo "[chromedriver] 警告: 无法获取 Chrome 版本"
        return 0
    fi
    local chrome_major="${chrome_version%%.*}"

    echo "[chromedriver] Chrome 浏览器:   $chrome_version (主版本: $chrome_major)"
    echo "[chromedriver] ChromeDriver:    $cd_version (主版本: $cd_major)"

    if [ "$cd_major" != "$chrome_major" ]; then
        echo ""
        echo "⚠️  ChromeDriver 版本不匹配！"
        echo "   Chrome 主版本:        $chrome_major"
        echo "   ChromeDriver 主版本:   $cd_major"
        echo ""
        echo "   系统 chromedriver 将被跳过，由 webdriver-manager 自动下载匹配版本。"
        echo "   如需使用系统 chromedriver，请升级 Chrome 或降级 chromedriver："
        echo "     brew upgrade --cask google-chrome"
        echo ""
    fi

    echo "[chromedriver] ✓ 版本匹配"
}

_check_chromedriver_version

# ---- 清理可能残留的 webdriver-manager 锁文件 ----
rm -f "$HOME/.wdm/.wdm-lock-"* 2>/dev/null || true

# ---- 启动 mock backend ----
if [ "$NO_MOCK" = "false" ]; then
    echo ""
    echo "[mock] 启动 mock backend..."
    MOCK_PORT="${BASE_URL##*:}"
    # 确保 mock_backend 能找到 Flutter Web 构建产物
    export MOCK_BACKEND_PORT="$MOCK_PORT"
    python mock_backend.py &
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
# 避免本地代理干扰 ChromeDriver ↔ Chrome 通信
export NO_PROXY="localhost,127.0.0.1,::1"
export no_proxy="$NO_PROXY"
export TEST_BASE_URL="$BASE_URL"
export TEST_BROWSER="$BROWSER"
export TEST_HEADLESS="$HEADLESS"
export TEST_USERNAME="${TEST_USERNAME:-admin}"
export TEST_PASSWORD="${TEST_PASSWORD:-password}"
export TEST_DEBUG="${DEBUG:-false}"

echo ""
echo "=============================="
echo "  目标: $BASE_URL"
echo "  Mock:  $MOCK_BACKEND_URL"
echo "  浏览器: $BROWSER"
echo "  Headless: $HEADLESS"
echo "  测试: $TEST_TARGET"
echo "=============================="
echo ""

pytest $TEST_TARGET -v "${PYTEST_ARGS[@]}"
