#!/bin/bash
# ============================================
# 调试后端服务（开发模式）
# ============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 检查虚拟环境
if [ ! -f ".venv/bin/python" ]; then
    echo "❌ 虚拟环境不存在，正在创建..."
    python3 -m venv .venv
fi

# 使用虚拟环境的 Python 直接运行
PYTHON=".venv/bin/python"

# 检查并安装依赖
if ! $PYTHON -c "import uvicorn" 2>/dev/null; then
    echo "📦 正在安装依赖..."
    $PYTHON -m pip install -r requirements.txt -q
    echo "✅ 依赖安装完成"
fi

echo "🔧 启动 Mobile Portainer 调试模式..."
echo "📍 地址: http://0.0.0.0:8000"
echo "📖 API 文档: http://0.0.0.0:8000/docs"
echo "🔄 热重载已启用（代码修改后自动重启）"
echo ""

$PYTHON -m uvicorn main:app \
    --host 0.0.0.0 \
    --port 8000 \
    --reload \
    --reload-dir app \
    --log-level debug
