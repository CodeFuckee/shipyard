#!/bin/bash
# ============================================
# 启动后端服务（生产模式）
# ============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 检查虚拟环境
if [ ! -f ".venv/bin/python" ]; then
    echo "❌ 虚拟环境不存在，正在创建..."
    python3 -m venv .venv
fi

# 使用虚拟环境的 Python 直接运行，避免 source 的兼容性问题
PYTHON=".venv/bin/python"

# 检查并安装依赖
if ! $PYTHON -c "import uvicorn" 2>/dev/null; then
    echo "📦 正在安装依赖..."
    $PYTHON -m pip install -r requirements.txt -q
    echo "✅ 依赖安装完成"
fi

# 检查前端是否已构建
if [ ! -f "static/index.html" ]; then
    echo "⚠️  前端未构建，正在构建..."
    if [ -f "frontend/package.json" ]; then
        cd frontend && npm install && npm run build && cd ..
        echo "✅ 前端构建完成"
    else
        echo "⚠️  未找到前端项目，跳过"
    fi
fi

echo "🚀 启动 Mobile Portainer 服务..."
echo "📍 地址: http://0.0.0.0:8000"
echo "📖 API 文档: http://0.0.0.0:8000/docs"
echo ""

$PYTHON -m uvicorn main:app --host 0.0.0.0 --port 8000
