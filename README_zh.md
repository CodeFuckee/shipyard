# Shipyard 🚢

移动端容器管理平台 — 随时随地管理你的 Docker 容器。

[English](README.md) | [中文](README_zh.md)

一个跨平台的 Docker 环境管理工具，由 **Python FastAPI 后端** 和 **Flutter 移动端** 组成。支持在手机、桌面浏览器或 macOS 上管理多个 Docker 主机，提供实时监控和完整的容器生命周期控制。

支持的平台：**Android · iOS · macOS · Web · OpenHarmony**

## ✨ 主要功能

### 🖥️ 服务器管理
- **多服务器支持**：添加和管理多个 Docker 端点，兼容 Portainer API
- **仪表盘概览**：服务器状态一览 — 容器数、镜像数、Docker 信息、Git 版本
- **资源监控**：实时可视化服务器资源（CPU、内存、磁盘）
- **GPU 监控**：NVIDIA GPU 温度、负载和显存使用
- **安全**：TLS/SSL 支持，可选择忽略自签名证书

### 📦 容器管理
- 按状态（运行中、已停止、已退出等）或按 Stack 查看容器
- 网格/列表视图切换，宽屏支持主从布局
- 完整的容器操作：创建、启动、停止、重启、暂停、恢复、终止、删除
- 容器详情：检查配置、实时状态、日志流、环境变量、网络、存储、文件浏览和下载

### 🖼️ 镜像 / 📚 Stack / 💾 卷 & 网络管理
- 列出、拉取、删除镜像
- 查看 Docker Compose Stack 并按 Stack 过滤容器
- 列出、检查、删除卷和网络

### 🛠️ 项目管理
- 创建项目（或从 Git 仓库克隆），自动生成 Dockerfile / docker-compose.yaml 模板
- 在线编辑 Dockerfile 与 docker-compose.yaml，实时保存
- 一键构建 Docker 镜像，WebSocket 实时推送构建日志
- 一键 docker compose 启动 / 停止容器
- 删除项目：每个项目卡片右上角删除按钮，确认后停止容器、删除数据库记录并清理服务器上项目文件夹

### 🔌 MCP Server（后端）
- 内置 MCP (Model Context Protocol) 服务器，暴露 **24 个 Docker 管理工具**
- 支持 Claude Desktop、Cursor 等 AI 助手通过自然语言管理 Docker 资源

### 🤖 AI 供应商配置（设置页）
- 纯配置存储，为后续 AI 功能做准备；API Key 加密存储，任何接口不返回明文
- 内置 deepseek / openai 预设（自动填充 Base URL 与默认模型），支持自定义供应商
- 设置页增删改供应商列表，保存后重启不丢失
- 「测试连接」按钮验证 Base URL 与 API Key（OpenAI 兼容 `/models` 端点）

### 🔗 Hermes 接入（设置页）
- 后端可接入其他设备上部署的 hermes 实例（OpenAI 兼容 API），调用其 AI 能力
- 通过环境变量配置（`HERMES_BASE_URL` / `HERMES_API_KEY` / `HERMES_MODEL`），未配置时自动禁用
- 设置页"Hermes 接入"入口：查看接入状态（启用、实例地址、模型、Key 状态）+「测试连接」
- 后端 API：`GET /admin/hermes/status`、`POST /admin/hermes/chat`（非流式）、`POST /admin/hermes/chat/stream`（SSE 流式）

### 🎨 用户体验
- 深色模式 / 浅色模式，跟随系统偏好
- 中英文国际化支持
- WebSocket 实时事件推送
- 本地推送通知
- 响应式设计，适配手机、平板和桌面

## 📂 项目结构

```
shipyard/
├── backend/              # Python FastAPI 后端
│   ├── app/
│   │   ├── core/         # 核心配置、安全、工具
│   │   ├── db/           # 数据库模型和连接
│   │   ├── mcp/          # MCP 服务器
│   │   ├── routers/      # API 路由
│   │   └── services/     # 后台服务
│   ├── docker-compose.yml
│   ├── Dockerfile
│   └── main.py           # 应用入口
├── frontend/             # Flutter 移动端
│   └── lib/
│       ├── models/       # 数据模型
│       ├── screens/      # UI 页面
│       ├── services/     # 服务层（Docker API、认证、平台抽象）
│       ├── theme/        # 主题
│       ├── utils/        # 工具
│       └── widgets/      # 可复用组件
└── README.md
```

## 🚀 快速开始

### 前提条件
- [Docker](https://docs.docker.com/get-docker/) 和 [Docker Compose](https://docs.docker.com/compose/install/)
- 移动端开发：[Flutter SDK](https://flutter.dev/) 3.35.8+（Dart 3.9.2+）
- 后端开发：Python 3.9+

### Docker Compose 一键部署（推荐）

创建 `docker-compose.yml`：

```yaml
version: '3.8'

services:
  api:
    image: codefuckee/mobile-portainer-api:latest
    container_name: mobile-portainer-api
    restart: unless-stopped
    environment:
      - ADMIN_USER=admin
      - ADMIN_PASSWORD=password
      - IGNORED_EVENTS=exec_create,exec_start,exec_die
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/app/data
      - /proc:/hostfs/proc:ro
    networks:
      - shipyard

  web:
    image: codefuckee/mobile-portainer-web:latest
    container_name: mobile-portainer-web
    restart: unless-stopped
    ports:
      - "8080:80"
    depends_on:
      - api
    networks:
      - shipyard

networks:
  shipyard:
    driver: bridge
```

```bash
docker compose up -d
```

访问 `http://localhost:8080`，使用后端管理员凭据登录。

### 本地开发

**后端：**

```bash
cd backend
python3 main.py
# 或: uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

启动后访问：
- Web Admin UI：http://localhost:8000
- API 文档 (Swagger)：http://localhost:8000/docs
- API 文档 (ReDoc)：http://localhost:8000/redoc

**前端：**

```bash
cd frontend
flutter pub get
flutter run -d chrome      # Web
flutter run -d macos       # macOS
flutter run                # Android / iOS（需连接设备）
```

### 后端独立部署

```bash
docker run -d \
  --name mobile-portainer \
  -p 8000:8000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v mobile_portainer_data:/app/data \
  -v /:/hostfs:ro \
  -e ADMIN_USER=admin \
  -e ADMIN_PASSWORD=password \
  --restart unless-stopped \
  codefuckee/mobile_portainer:latest
```

## ⚙️ 环境变量

| 变量名 | 默认值 | 说明 |
| :--- | :--- | :--- |
| `ADMIN_USER` | `admin` | Web Admin UI 用户名 |
| `ADMIN_PASSWORD` | `password` | Web Admin UI 密码 |
| `IGNORED_EVENTS` | `exec_create,exec_start,exec_die` | Docker 事件流中忽略的事件类型 |
| `HOST_FILESYSTEM_ROOT` | `/hostfs` | 容器内主机根目录挂载路径 |
| `BACKUP_DIR` | `data/backups/` | 备份文件存储目录 |
| `BACKUP_CRON` | (空) | 定时备份 cron 表达式（如 `0 3 * * *`）；为空则禁用 |
| `BACKUP_KEEP_DAYS` | `30` | 旧备份自动清理保留天数 |
| `BACKUP_SCHEDULE_FILE` | `data/backup_schedule.json` | Web UI 写入的调度配置文件；优先于 `BACKUP_CRON` |
| `HERMES_BASE_URL` | (空) | Hermes 实例地址（如 `https://hermes.example.com/v1`）；为空则禁用 Hermes 接入 |
| `HERMES_API_KEY` | (空) | Hermes 访问密钥（可选，多数自部署实例不需要） |
| `HERMES_MODEL` | (空) | Hermes 默认模型名（可选，留空由服务端默认） |

## 🛠️ 技术栈

| 层 | 技术 |
| :--- | :--- |
| **后端** | Python 3.9+, FastAPI, SQLAlchemy, SQLite, MCP |
| **前端** | Flutter 3.35.8, Dart 3.9.2 |
| **部署** | Docker, Docker Compose, Nginx |
| **CI/CD** | GitLab CI |

### 前端关键依赖
- `http` + 自定义 `HttpHelper`：跨平台 API 通信
- `web_socket_channel` + 自定义 `WsHelper`：实时 WebSocket 事件
- `shared_preferences`：本地存储（含 OpenHarmony 回退）
- `flutter_localizations` + `intl`：国际化（英文 & 中文）
- `flutter_local_notifications`：本地推送通知
- `mobile_scanner`：二维码扫描

## 📱 截图

详细截图请参见 [frontend/README.md](frontend/README.md#-screenshots)。

## 🔌 MCP Server

后端内置 MCP (Model Context Protocol) 服务器，允许 AI 助手通过自然语言管理 Docker 资源。支持 **24 个工具**，涵盖容器、镜像、网络、卷和系统五大类别。

```bash
# 启动 MCP 服务器
python -m app.mcp.server
```

Claude Desktop 配置示例：

```json
{
  "mcpServers": {
    "mobile-portainer": {
      "command": "python",
      "args": ["-m", "app.mcp.server"],
      "env": {
        "MOBILE_PORTAINER_API_KEY": "your-api-key"
      }
    }
  }
}
```

## 📝 API 使用示例

所有受保护的 API 端点需要 `X-API-Key` 请求头：

```http
GET /containers/json HTTP/1.1
Host: localhost:8000
X-API-Key: <从 Web Admin UI 生成的 API Key>
```

API Key 可在登录 Web Admin UI (`/`) 后生成和管理。

## 📄 License

MIT License — 详见 [LICENSE](LICENSE) 文件。
