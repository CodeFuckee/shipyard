# Mobile Portainer API

[English](README.md) | [中文](README_zh.md)

A lightweight Docker management API service built with [FastAPI](https://fastapi.tiangolo.com/). It is designed to provide a simple interface for mobile applications to manage Docker containers, images, networks, and volumes. It also includes a simple Web Admin UI for managing API keys and cluster nodes.

> **📱 Companion App**: This API is designed to work with the Mobile Portainer Flutter App.  
> 👉 **Get the App**: [https://github.com/CodeFuckee/mobile_portainer_flutter](https://github.com/CodeFuckee/mobile_portainer_flutter)

## ✨ Features

- **Docker Management**:
  - **Containers**: List, inspect details, view logs, resource stats, start, stop, restart, kill, remove, **browse files**, **download files**.
  - **Images**: List, pull new images, remove, inspect details.
  - **Networks**: List, inspect details, create, remove.
  - **Volumes**: List, inspect details, create, remove, **browse files**.
  - **System**: Get Docker system info, version, real-time events stream.
- **Security**:
  - Core API endpoints are protected by `X-API-Key`.
  - Web Admin UI is protected by Basic Auth.
- **Web Admin UI**:
  - Intuitive interface to manage API Access Keys.
  - Manage Cluster Nodes information.
- **Auto Update**:
  - Built-in Git auto-update service that can be configured to periodically check the remote repository and update/restart automatically.
- **System Monitoring**:
  - Supports mounting the host root directory for monitoring host resource usage.
- **MCP Server**:
  - Built-in MCP (Model Context Protocol) server that exposes 24 Docker management tools for AI assistants (e.g., Claude Desktop).
  - Manage containers, images, networks, volumes, and system resources directly through natural language conversations.

## 🛠️ Tech Stack

- **Language**: Python 3.9+
- **Web Framework**: FastAPI
- **Database**: SQLite (managed via SQLAlchemy ORM)
- **Docker Interaction**: Docker SDK for Python
- **Deployment**: Docker / Docker Compose

## 🚀 Quick Start

### 1. Prerequisites

Ensure your server has the following installed:
- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)

### 2. Install & Run

#### Option A: Build from Source (Docker Compose)

Start the service directly using Docker Compose:

```bash
# Build and start in detached mode
docker-compose up -d --build
```

#### Option B: Run from Docker Hub

You can also run the pre-built image directly:

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

### 3. Access the Service

Once started, you can access the following:

- **Web Admin UI**: [http://localhost:8000](http://localhost:8000)
  - Default Username: `admin`
  - Default Password: `password`
  - *Please change the default password in `docker-compose.yml` for production environments!*
- **API Documentation (Swagger UI)**: [http://localhost:8000/docs](http://localhost:8000/docs)
- **API Documentation (ReDoc)**: [http://localhost:8000/redoc](http://localhost:8000/redoc)

## ⚙️ Environment Variables

You can configure the service by modifying the `environment` section in `docker-compose.yml`:

| Variable Name | Default Value | Description |
| :--- | :--- | :--- |
| `ADMIN_USER` | `admin` | Username for Web Admin UI |
| `ADMIN_PASSWORD` | `...` | Password for Web Admin UI |
| `IGNORED_EVENTS` | `exec_create,exec_start,exec_die` | Event types to ignore in Docker event stream |
| `HOST_FILESYSTEM_ROOT` | `/hostfs` | Mount path of host root directory inside container |

## 📂 Project Structure

```text
.
├── app/
│   ├── core/           # Core config, security, utils
│   ├── db/             # Database models and connection
│   ├── mcp/            # MCP server (Model Context Protocol) tools and entry point
│   ├── routers/        # API routers (Containers, Images, WebUI, etc.)
│   ├── services/       # Background services (Docker Event Listener)
├── data/               # Data persistence directory (SQLite database)
├── docker-compose.yml  # Docker Compose orchestration file
├── Dockerfile          # Docker image build file
├── main.py             # FastAPI application entry point
└── requirements.txt    # Python dependencies
```

## 📝 API Usage Example

All protected API endpoints require the `X-API-Key` header.

**Get Container List:**

```http
GET /containers/json HTTP/1.1
Host: localhost:8000
X-API-Key: <Your-API-Key-From-Web-UI>
```

You can generate and manage these API Keys after logging into the Web Admin UI (`/`).

## 🔌 MCP Server

Mobile Portainer includes a built-in [MCP (Model Context Protocol)](https://modelcontextprotocol.io) server that allows AI assistants (such as Claude Desktop, Cursor, and other MCP-compatible clients) to manage Docker resources directly through natural language conversations.

### How It Works

The MCP server runs as a standalone subprocess communicating via **stdio**. It does NOT run as part of the FastAPI HTTP service — instead, it is spawned directly by the AI client. The server exposes **24 Docker management tools** across 5 categories:

| Category | Tools |
| :--- | :--- |
| **Containers** | `list_containers`, `get_container`, `get_container_logs`, `start_container`, `stop_container`, `restart_container`, `kill_container`, `pause_container`, `unpause_container`, `remove_container`, `run_container` |
| **Images** | `list_images`, `get_image`, `pull_image`, `remove_image` |
| **Networks** | `list_networks`, `get_network` |
| **Volumes** | `list_volumes`, `get_volume`, `remove_volume` |
| **System** | `get_system_info`, `get_system_usage`, `list_stacks`, `get_stack_containers` |

The `get_system_info` tool aggregates Docker stats, Git version info, and system resource usage into a single response. The `run_container` tool parses natural `docker run`-style commands, so you can ask "run nginx in the background" and it just works.

### Starting the Server

```bash
python -m app.mcp.server
```

### Claude Desktop Configuration

Add the following to your `claude_desktop_config.json`:

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

### Authentication

The MCP server checks API keys in the following priority order:

1. **Environment variable** — If `MOBILE_PORTAINER_API_KEY` is set, the key must match exactly.
2. **Database fallback** — If no environment variable is set, it looks up the key in the `api_keys` database table (keys managed via the Web Admin UI).
3. **No-auth mode** — If neither is configured, all requests are allowed through.

> ⚠️ For production use, it's strongly recommended to set `MOBILE_PORTAINER_API_KEY` or manage keys via the Web Admin UI.
