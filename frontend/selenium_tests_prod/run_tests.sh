#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ---- 默认参数 ----
PROD_URLS="${TEST_PROD_URLS:-https://home.chenkaidi.top:507,http://10.0.0.122:8080}"
BROWSER="${TEST_BROWSER:-chrome}"
HEADLESS="${TEST_HEADLESS:-true}"
TEST_TARGET="tests/"
# -s 默认开启：首帧加载时间等测量类 print 输出进入 pytest_output.log
# （CI artifacts 的"最终测试结果"），失败排查也依赖完整日志
PYTEST_ARGS=(-s)
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

# ---- 凭据注入：环境变量 > 脚本目录 .env 文件 > launchctl（macOS） ----
# 用户常见误区：export 后另开终端窗口导致变量丢失，或变量只在 GUI 会话
# （launchctl setenv）可见而终端 shell 看不到。此处提供多级兜底，
# 任何一级命中都不再跳过登录测试；全部缺失时打印醒目警告。
# .env 文件已被根 .gitignore 忽略，凭据不会入库。

# 1) 脚本目录 .env 文件（不覆盖已有的环境变量）：
#    加载全部凭据变量，含 per-host 变体（TEST_USERNAME_<host> /
#    TEST_PASSWORD_<host>，见 config.per_host_creds）
if [ -f "$SCRIPT_DIR/.env" ]; then
    while IFS='=' read -r _key _val2; do
        case "$_key" in
            ""|"#"*) continue ;;
            TEST_USERNAME_*|TEST_PASSWORD_*|TEST_USERNAME|TEST_PASSWORD|TEST_CONNECT_USERNAME|TEST_CONNECT_PASSWORD)
                if [ -z "${!_key:-}" ]; then
                    _val="${_val2%\"}"; _val="${_val#\"}"
                    export "$_key=$_val"
                fi
                ;;
        esac
    done < "$SCRIPT_DIR/.env"
fi

_load_env_fallback() {
    local _var="$1" _val=""
    # macOS launchctl（GUI 应用继承的会话变量，终端 shell 默认不可见）
    if [ "$(uname)" = "Darwin" ]; then
        _val="$(launchctl getenv "$_var" 2>/dev/null || true)"
    fi
    if [ -n "$_val" ]; then
        export "$_var=$_val"
    fi
    return 0  # set -e 下必须显式成功返回，否则空凭据时脚本直接退出
}

for _CRED_VAR in TEST_USERNAME TEST_PASSWORD TEST_CONNECT_USERNAME TEST_CONNECT_PASSWORD; do
    if [ -z "${!_CRED_VAR}" ]; then
        _load_env_fallback "$_CRED_VAR"
    fi
done

if [ -z "$TEST_USERNAME" ] || [ -z "$TEST_PASSWORD" ]; then
    echo ""
    echo "  [警告] TEST_USERNAME / TEST_PASSWORD 未设置（已检查环境变量、.env 文件、launchctl）"
    echo "         登录相关测试（test_prod_connect.py）将被跳过。"
    echo "         注入方式："
    echo "           export TEST_USERNAME=xxx TEST_PASSWORD=yyy"
    echo "           或写入 $SCRIPT_DIR/.env："
    echo "             TEST_USERNAME=xxx"
    echo "             TEST_PASSWORD=yyy"
    echo ""
fi

# ---- 创建/检查虚拟环境 ----
if [ ! -d "venv" ]; then
    echo "[setup] 创建虚拟环境..."
    python3 -m venv venv
fi

echo "[setup] 激活虚拟环境..."
source venv/bin/activate

# ---- 安装依赖 ----
# 每次运行增量安装：pip 对已安装且版本满足的包快速跳过（无网络请求），
# requirements.txt 新增的包会自动装上。不能只在 import 检查失败时才
# 安装——CI 构建目录的 venv 跨 job 持久化复用，旧条件（仅检查 selenium）
# 会导致新增依赖永远装不上（流水线 435 的 lxml ModuleNotFoundError）。
echo "[setup] 安装依赖..."
pip install -r requirements.txt -q

echo "[setup] 依赖 OK"

# 避免本地代理干扰 ChromeDriver ↔ Chrome 通信；生产环境地址也加入
# 绕过列表（浏览器对私网地址默认绕过代理直连，Python/Chrome 也应一致）
PROXY_BYPASS="localhost,127.0.0.1,::1"
for _u in ${PROD_URLS//,/ }; do
    _h="${_u#*://}"
    _h="${_h%%[:/]*}"
    case ",$PROXY_BYPASS," in
        *",$_h,"*) ;;
        *) PROXY_BYPASS="$PROXY_BYPASS,$_h" ;;
    esac
done
export NO_PROXY="$PROXY_BYPASS"
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
