# Shipyard 🚢

A mobile container management platform — manage your Docker containers anytime, anywhere.

[English](README.md) | [中文](README_zh.md)

A cross-platform Docker environment management tool, consisting of a **Python FastAPI backend** and a **Flutter mobile frontend**. Manage multiple Docker hosts from your mobile device, desktop browser, or macOS — with real-time monitoring and full container lifecycle control.

Supported platforms: **Android · iOS · macOS · Web · OpenHarmony**

## ✨ Key Features

### 🖥️ Server Management
- **Multi-Server Support**: Add and manage multiple Docker endpoints with Portainer-compatible APIs.
- **Dashboard Overview**: At-a-glance server status — container counts, image counts, Docker info, and Git version.
- **Resource Monitoring**: Real-time visualization of CPU, memory, and disk usage.
- **GPU Monitoring**: NVIDIA GPU temperature, load, and memory usage.
- **Security**: TLS/SSL support with option to ignore self-signed certificates.

### 📦 Container Management
- View containers by status (Running, Stopped, Exited, etc.) or by Stacks.
- Grid/List view toggle, master-detail layout on wide screens.
- Full container lifecycle: Create, Start, Stop, Restart, Pause, Unpause, Kill, Remove, and Upgrade (update container to the latest image version while preserving ports, mounts, and environment variables).
- Container details: Inspect configuration, real-time stats, log streaming, environment variables, network, storage, file browsing and download.

### 🖼️ Images / 📚 Stacks / 💾 Volumes & Networks
- List, pull, and remove images.
- View Docker Compose stacks and filter containers by stack.
- List, inspect, and remove volumes and networks.

### 🛠️ Project Management
- Create projects (or clone from a Git repository) with auto-generated Dockerfile / docker-compose.yaml templates.
- Edit Dockerfile and docker-compose.yaml online with instant saving.
- Build Docker images with real-time build logs pushed over WebSocket.
- Start / stop containers with one-click `docker compose up/down`.
- Delete projects: delete icon on each project card, with a confirmation dialog. Deleting stops containers, removes the database record and cleans up the project folder on the server.

### 🔌 MCP Server (Backend)
- Built-in MCP (Model Context Protocol) server exposing **24 Docker management tools**.
- Manage Docker resources through natural language with AI assistants like Claude Desktop and Cursor.

### 🤖 AI Provider Settings (Settings Page)
- Pure configuration storage to prepare for future AI features; API Keys are encrypted and never returned by any endpoint.
- Built-in 70+ preset providers (based on cc-switch, each with its own logo; auto-fill name / Base URL and default model on selection), plus fully custom providers.
- Add / edit / delete providers in the Settings page; persisted across restarts.
- "Test Connection" verifies Base URL and API Key against the OpenAI-compatible `/models` endpoint.

### 🔗 Hermes Integration (Settings Page)
- Connect to hermes instances deployed on other devices (OpenAI-compatible API) and call their AI capabilities.
- Configured via environment variables (`HERMES_BASE_URL` / `HERMES_API_KEY` / `HERMES_MODEL`); auto-disabled when not configured.
- "Hermes Integration" entry in Settings: view status (enabled, instance URL, model, key state) + "Test Connection".
- Backend API: `GET /admin/hermes/status`, `POST /admin/hermes/chat` (non-streaming), `POST /admin/hermes/chat/stream` (SSE streaming).

### 🤖 Image Pull Agent (Backend)
- LangChain-based agent that uses the two `backend/skills` skills (docker-mirror-pull / docker-pull-from-file) to pull Docker images.
- Natural-language commands: single image ("pull nginx:1.25") or batch from a file ("pull all images from docker-compose.yml"); the agent automatically tries domestic mirror prefixes until success.
- LLM reuses the Hermes integration config; when no model is set, it auto-probes the first model from `{base}/models`.
- Backend API: `GET /admin/agent/status` (status + active mirror prefixes), `POST /admin/agent/chat` (conversation; returns the final reply and execution steps).
- Override the mirror list with the `AGENT_MIRROR_PREFIXES` environment variable.

### 🎨 User Experience
- Dark mode / Light mode, follows system preference.
- Internationalization: English and Chinese (zh-CN).
- WebSocket integration for real-time event streaming.
- Local push notifications.
- Responsive design for mobile, tablet, and desktop.

## 📂 Project Structure

```
shipyard/
├── backend/              # Python FastAPI backend
│   ├── app/
│   │   ├── core/         # Core config, security, utilities
│   │   ├── db/           # Database models and connection
│   │   ├── mcp/          # MCP server
│   │   ├── routers/      # API routers
│   │   └── services/     # Background services
│   ├── docker-compose.yml
│   ├── Dockerfile
│   └── main.py           # Application entry point
├── frontend/             # Flutter mobile frontend
│   └── lib/
│       ├── models/       # Data models
│       ├── screens/      # UI screens
│       ├── services/     # Service layer (Docker API, auth, platform abstraction)
│       ├── theme/        # Theming
│       ├── utils/        # Utilities
│       └── widgets/      # Reusable UI components
└── README.md
```

## 🚀 Getting Started

### Prerequisites
- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/)
- Mobile development: [Flutter SDK](https://flutter.dev/) 3.35.8+ (Dart 3.9.2+)
- Backend development: Python 3.9+

### Docker Compose (Recommended)

Create a `docker-compose.yml`:

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

Visit `http://localhost:8080` and log in with your backend admin credentials.

### Local Development

**Backend:**

```bash
cd backend
python3 main.py
# Or: uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

After starting, access:
- Web Admin UI: http://localhost:8000
- API Docs (Swagger): http://localhost:8000/docs
- API Docs (ReDoc): http://localhost:8000/redoc

**Frontend:**

```bash
cd frontend
flutter pub get
flutter run -d chrome      # Web
flutter run -d macos       # macOS
flutter run                # Android / iOS (requires connected device)
```

### Backend Standalone Deployment

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

## ⚙️ Environment Variables

| Variable | Default | Description |
| :--- | :--- | :--- |
| `ADMIN_USER` | `admin` | Username for Web Admin UI |
| `ADMIN_PASSWORD` | `password` | Password for Web Admin UI |
| `IGNORED_EVENTS` | `exec_create,exec_start,exec_die` | Event types to ignore in Docker event stream |
| `HOST_FILESYSTEM_ROOT` | `/hostfs` | Mount path of host root directory inside container |
| `BACKUP_DIR` | `data/backups/` | Directory where backup files are stored |
| `BACKUP_CRON` | (empty) | Cron expression for scheduled auto-backup (e.g. `0 3 * * *`); empty disables it |
| `BACKUP_KEEP_DAYS` | `30` | Days to keep old backups before auto-cleanup |
| `BACKUP_SCHEDULE_FILE` | `data/backup_schedule.json` | Schedule config file written by the Web UI; takes precedence over `BACKUP_CRON` |
| `HERMES_BASE_URL` | (empty) | Hermes instance URL (e.g. `https://hermes.example.com/v1`); empty disables Hermes integration |
| `HERMES_API_KEY` | (empty) | Hermes access key (optional; most self-hosted instances don't need one) |
| `HERMES_MODEL` | (empty) | Default model name for Hermes (optional; server default used when empty) |
| `AGENT_MIRROR_PREFIXES` | (empty) | Comma-separated mirror prefixes used by the Image Pull Agent; empty falls back to the built-in 7 mirrors |
| `AGENT_MAX_ITERATIONS` | `10` | Max tool iterations per agent conversation |
| `AGENT_PULL_TIMEOUT` | `600` | Per-pull timeout in seconds for the agent |

## 🛠️ Tech Stack

| Layer | Technology |
| :--- | :--- |
| **Backend** | Python 3.9+, FastAPI, SQLAlchemy, SQLite, MCP |
| **Frontend** | Flutter 3.35.8, Dart 3.9.2 |
| **Deployment** | Docker, Docker Compose, Nginx |
| **CI/CD** | GitLab CI |

### Key Frontend Dependencies
- `http` + custom `HttpHelper`: Cross-platform API communication
- `web_socket_channel` + custom `WsHelper`: Real-time WebSocket events
- `shared_preferences`: Local storage (with OpenHarmony fallback)
- `flutter_localizations` + `intl`: Internationalization (English & Chinese)
- `flutter_local_notifications`: Local push notifications
- `mobile_scanner`: QR code scanning

## 📱 Screenshots

See [frontend/README.md](frontend/README.md#-screenshots) for detailed screenshots.

## 🔌 MCP Server

The backend includes a built-in MCP (Model Context Protocol) server, enabling AI assistants to manage Docker resources through natural language. It provides **24 tools** across 5 categories: Containers, Images, Networks, Volumes, and System.

```bash
# Start the MCP server
python -m app.mcp.server
```

Claude Desktop configuration example:

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

## 📝 API Usage

All protected API endpoints require the `X-API-Key` header:

```http
GET /containers/json HTTP/1.1
Host: localhost:8000
X-API-Key: <Your-API-Key-From-Web-Admin-UI>
```

API keys can be generated and managed after logging into the Web Admin UI (`/`).

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.
