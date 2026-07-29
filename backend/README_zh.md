# Mobile Portainer API

[English](README.md) | [中文](README_zh.md)

这是一个基于 [FastAPI](https://fastapi.tiangolo.com/) 构建的轻量级 Docker 管理 API 服务。它旨在为移动端应用提供简洁的 Docker 容器、镜像、网络和卷的管理接口，同时也包含了一个简单的 Web 管理界面用于管理 API 密钥和集群节点。

> **📱 配套客户端**: 本项目专为 Mobile Portainer 移动端应用设计。  
> 👉 **获取客户端**: [https://github.com/CodeFuckee/mobile_portainer_flutter](https://github.com/CodeFuckee/mobile_portainer_flutter)

## ✨ 主要功能

- **Docker 管理**:
  - **容器 (Containers)**: 获取列表、查看详情、查看日志、资源统计、启动、停止、重启、强制停止、删除、**浏览文件**、**下载文件**。
  - **镜像 (Images)**: 镜像列表查询、拉取新镜像、删除镜像、查看镜像详情。
  - **网络 (Networks)**: 网络列表、查看网络详情、创建网络、删除网络。
  - **卷 (Volumes)**: 卷列表、查看卷详情、创建卷、删除卷、**浏览文件**。
  - **系统 (System)**: 获取 Docker 系统信息、版本信息、实时事件流 (Events)。
- **安全认证**:
  - 核心 API 接口采用 `X-API-Key` 进行访问控制。
  - Web 管理后台采用 Basic Auth 登录保护。
- **Web 管理界面**:
  - 提供直观的界面管理 API 访问密钥 (API Keys)。
  - 管理多节点集群信息 (Cluster Nodes)。
- **自动更新**:
  - 内置 Git 自动更新服务，可配置定时检查远程仓库并自动更新重启。
- **系统监控**:
  - 支持挂载宿主机根目录，用于监控宿主机资源使用情况。
- **MCP Server**:
  - 内置 MCP (Model Context Protocol) 服务，为 AI 助手（如 Claude Desktop）暴露 24 个 Docker 管理工具。
  - 通过自然语言对话即可管理容器、镜像、网络、卷和系统资源。

## 🛠️ 技术栈

- **编程语言**: Python 3.9+
- **Web 框架**: FastAPI
- **数据库**: SQLite (通过 SQLAlchemy ORM 管理)
- **Docker 交互**: Docker SDK for Python
- **部署方式**: Docker / Docker Compose

## 🚀 快速开始

### 1. 前置要求

确保你的服务器上已安装：
- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)

### 2. 安装与运行

#### 方式 A: 源码构建 (Docker Compose)

直接使用 Docker Compose 启动服务：

```bash
# 构建并后台启动
docker-compose up -d --build
```

#### 方式 B: 使用 Docker 镜像

你也可以直接拉取构建好的镜像运行：

**Docker CLI:**

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

**Docker Compose:**

```yaml
version: '3.8'
services:
  api:
    image: codefuckee/mobile_portainer:latest
    ports:
      - "8000:8000"
    environment:
      - ADMIN_USER=admin
      - ADMIN_PASSWORD=password
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/app/data
      - /:/hostfs:ro
    restart: unless-stopped
```

### 3. 访问服务

启动成功后，可以通过以下地址访问：

- **Web 管理后台**: [http://localhost:8000](http://localhost:8000)
  - 默认用户名: `admin`
  - 默认密码: `password`
  - *请在生产环境中修改 `docker-compose.yml` 中的默认密码！*
- **API 文档 (Swagger UI)**: [http://localhost:8000/docs](http://localhost:8000/docs)
- **API 文档 (ReDoc)**: [http://localhost:8000/redoc](http://localhost:8000/redoc)

## ⚙️ 环境变量配置

可以通过修改 `docker-compose.yml` 中的 `environment` 部分来配置服务：

| 变量名 | 默认值 | 说明 |
| :--- | :--- | :--- |
| `ADMIN_USER` | `admin` | Web 管理界面的登录用户名 |
| `ADMIN_PASSWORD` | `...` | Web 管理界面的登录密码 |
| `IGNORED_EVENTS` | `exec_create,exec_start,exec_die` | Docker 事件流中忽略的事件类型 |
| `HOST_FILESYSTEM_ROOT` | `/hostfs` | 宿主机根目录在容器内的挂载路径 |
| `SMTP_HOST` | 空 | SMTP 服务器地址；配置后可调用邮件发送接口 |
| `SMTP_PORT` | `587` | SMTP 端口 |
| `SMTP_USERNAME` | 空 | SMTP 登录用户名（可选） |
| `SMTP_PASSWORD` | 空 | SMTP 登录密码或授权码（仅环境变量保存，接口不返回） |
| `SMTP_FROM_EMAIL` | 空 | 发件人邮箱地址 |
| `SMTP_FROM_NAME` | `Mobile Portainer` | 发件人显示名称 |
| `SMTP_USE_SSL` | `false` | 是否使用 SMTP SSL（通常为 465 端口） |
| `SMTP_USE_STARTTLS` | `true` | 是否使用 STARTTLS（通常为 587 端口；与 SSL 不能同时启用） |
| `SMTP_TIMEOUT` | `10` | SMTP 连接与发送超时秒数 |

## ✉️ 发送邮件

配置 `SMTP_HOST` 和 `SMTP_FROM_EMAIL` 后，可使用已认证的管理员凭据或 API Key 调用以下接口。`GET /admin/email/config` 仅返回非敏感配置状态，`POST /admin/email/send` 将邮件发送给指定用户：

```http
POST /admin/email/send HTTP/1.1
Host: localhost:8000
X-API-Key: <API Key>
Content-Type: application/json

{
  "recipients": ["user@example.com"],
  "subject": "通知标题",
  "text_body": "纯文本内容",
  "html_body": "<p>可选 HTML 内容</p>"
}
```

## 📂 项目结构

```text
.
├── app/
│   ├── core/           # 核心配置、安全认证、工具函数
│   ├── db/             # 数据库模型 (Models) 与连接 (Database)
│   ├── mcp/            # MCP 服务 (Model Context Protocol) 工具与入口
│   ├── routers/        # API 路由模块 (Containers, Images, WebUI 等)
│   ├── services/       # 后台服务 (Docker Event Listener)
├── data/               # 数据持久化目录 (SQLite 数据库文件)
├── docker-compose.yml  # Docker Compose 编排文件
├── Dockerfile          # Docker 镜像构建文件
├── main.py             # FastAPI 应用入口
└── requirements.txt    # Python 依赖列表
```

## 📝 API 调用示例

所有受保护的 API 接口都需要在 HTTP Header 中包含 `X-API-Key`。

**获取容器列表:**

```http
GET /containers/json HTTP/1.1
Host: localhost:8000
X-API-Key: <在Web界面生成的API Key>
```

你可以在 Web 管理界面 (`/`) 登录后生成和管理这些 API Key。

## 🔌 MCP Server

Mobile Portainer 内置了 [MCP (Model Context Protocol)](https://modelcontextprotocol.io) 服务，允许 AI 助手（如 Claude Desktop、Cursor 和其他兼容 MCP 的客户端）通过自然语言对话直接管理 Docker 资源。

### 工作原理

MCP 服务以独立子进程方式运行，通过 **stdio** 与 AI 客户端通信。它**不**作为 FastAPI HTTP 服务的一部分运行 —— 而是由 AI 客户端直接拉起。该服务提供 **24 个 Docker 管理工具**，分为 5 类：

| 类别 | 工具 |
| :--- | :--- |
| **容器 (Containers)** | `list_containers`、`get_container`、`get_container_logs`、`start_container`、`stop_container`、`restart_container`、`kill_container`、`pause_container`、`unpause_container`、`remove_container`、`run_container` |
| **镜像 (Images)** | `list_images`、`get_image`、`pull_image`、`remove_image` |
| **网络 (Networks)** | `list_networks`、`get_network` |
| **卷 (Volumes)** | `list_volumes`、`get_volume`、`remove_volume` |
| **系统 (System)** | `get_system_info`、`get_system_usage`、`list_stacks`、`get_stack_containers` |

`get_system_info` 工具可将 Docker 统计信息、Git 版本信息和系统资源使用情况聚合到单次响应中。`run_container` 工具可解析自然的 `docker run` 风格命令，因此你可以直接说"在后台运行 nginx"，它就能正常工作。

### 启动服务

```bash
python -m app.mcp.server
```

### Claude Desktop 配置

将以下内容添加到 `claude_desktop_config.json` 中：

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

### 认证方式

MCP 服务按以下优先级验证 API Key：

1. **环境变量优先** — 如果设置了 `MOBILE_PORTAINER_API_KEY`，则 Key 必须完全匹配。
2. **数据库回退** — 如果未设置环境变量，则在 `api_keys` 数据库表中查找（通过 Web 管理界面管理的 Key）。
3. **无认证模式** — 如果两者均未配置，则允许所有请求通过。

> ⚠️ 生产环境建议务必设置 `MOBILE_PORTAINER_API_KEY` 或通过 Web 管理界面管理 Key。
