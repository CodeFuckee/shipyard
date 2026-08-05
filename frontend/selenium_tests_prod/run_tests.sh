#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ---- 默认参数 ----
PROD_URLS="${TEST_PROD_URLS:-https://home.chenkaidi.top:507,http://10.0.0.122:8080}"
BROWSER="${TEST_BROWSER:-chrome}"
HEADLESS="${TEST_HEADLESS:-true}"
TEST_TARGET="tests/"
PYTEST_ARGS=()
DEBUG="false"

# ---- 解析命令行参数 ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --urls=*)     PROD_URLS="${1#*=}"; shift ;;
        --urls)       PROD_URLS="$2"; shift 2 ;;
        --browser=*)  BROWSER="${1#*=}"; shift ;;
        --browser)    BROWSER="$2"; shift 2 ;;
        --headed)     HEADLESS="false"; shift ;;
        --debug)      HEADLESS="false"; DEBUG="true"; shift ;;
        -k)           PYTEST_ARGS+=("-k" "$2"); shift 2 ;;
        -v)           PYTEST_ARGS+=("-v"); shift ;;
        -s)           PYTEST_ARGS+=("-s"); shift ;;
        --html)       PYTEST_ARGS+=("--html=report.html" "--self-contained-html"); shift ;;
        -h|--help)
            echo "用法: ./run_tests.sh [选项] [测试文件/目录]"
            echo ""
            echo "生产环境只读冒烟测试 — 直接测试部署在生产环境的页面，"
            echo "与 frontend/selenium_tests（本地 mock 环境）区分。"
            echo ""
            echo "选项:"
            echo "  --urls=URLS      生产环境地址，逗号分隔多环境 (默认: $PROD_URLS)"
            echo "  --browser=NAME   浏览器: chrome | firefox (默认: chrome)"
            echo "  --headed         显示浏览器窗口"
            echo "  --debug          调试模式：显示浏览器 + 操作间停顿"
            echo "  --html           生成 HTML 报告"
            echo "  -k EXPR          按关键字筛选测试"
            echo "  -v               详细输出"
            echo "  -s               显示 print 输出"
            echo ""
            echo "环境变量:"
            echo "  TEST_PROD_URLS   生产环境地址（逗号分隔，默认见 --urls）"
            echo "  TEST_USERNAME    Portainer 用户名（登录测试必需）"
            echo "  TEST_PASSWORD    Portainer 密码（登录测试必需）"
            echo "  TEST_HEADLESS    是否无头模式 (true/false)"
            echo "  TEST_BROWSER     浏览器类型"
            echo "  TEST_DEBUG       调试模式 (true/false)"
            echo ""
            echo "示例:"
            echo "  TEST_USERNAME=admin TEST_PASSWORD=xxx ./run_tests.sh"
            echo "  ./run_tests.sh --urls=https://home.chenkaidi.top:507"
            echo "  ./run_tests.sh --headed -k nav"
            echo "  ./run_tests.sh --html"
            exit 0
            ;;
        *)  TEST_TARGET="$1"; shift ;;
    esac
done

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

# 避免本地代理干扰 ChromeDriver ↔ Chrome 通信
export NO_PROXY="localhost,127.0.0.1,::1"
export no_proxy="$NO_PROXY"
export TEST_PROD_URLS="$PROD_URLS"
export TEST_BROWSER="$BROWSER"
export TEST_HEADLESS="$HEADLESS"
export TEST_DEBUG="${DEBUG:-false}"

echo ""
echo "=============================="
echo "  生产环境: $PROD_URLS"
echo "  浏览器: $BROWSER"
echo "  Headless: $HEADLESS"
echo "  测试: $TEST_TARGET"
echo "  (只读冒烟，无写操作)"
echo "=============================="
echo ""

pytest $TEST_TARGET -v "${PYTEST_ARGS[@]}"
