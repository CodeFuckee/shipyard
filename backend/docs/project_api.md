# 项目 API 接口文档

本文档定义了「项目」功能所需的后端 API 接口，供后端程序实现参考。

---

## 基础信息

- **Base URL**: `{server_url}`（与现有 Docker 管理 API 相同的基础地址）
- **认证方式**: 
  - JWT Token: `Authorization: Bearer {token}`（token 以 `eyJ` 开头时）
  - API Key: `X-API-Key: {key}`（其他情况）
- **Content-Type**: `application/json`（除特殊说明外）
- **日期格式**: ISO 8601 格式（如 `2026-07-28T10:30:00Z`）

---

## 数据模型

### Project

```json
{
  "id": "string (项目唯一标识)",
  "name": "string (项目名称)",
  "description": "string (项目描述，可为空)",
  "status": "string (枚举: idle | building | running | failed)",
  "createdAt": "string (ISO 8601 日期时间)",
  "updatedAt": "string (ISO 8601 日期时间)"
}
```

### BuildLog

```json
{
  "stream": "string? (stdout 输出行，如 'Step 1/5 : FROM node:18')",
  "status": "string? (状态描述，如 'Building', 'Successfully built')",
  "error": "string? (错误信息)",
  "imageId": "string? (构建成功后返回的镜像 ID)",
  "isDone": "boolean (构建是否已完成)"
}
```

### 通用错误响应

```json
{
  "detail": "string (错误描述信息)",
  "message": "string (备选错误字段)",
  "error": "string (备选错误字段)"
}
```

HTTP 状态码：`4xx` 客户端错误，`5xx` 服务端错误。

---

## REST API 端点

### 1. 获取项目列表

```
GET /projects
```

**请求**: 无特殊参数

**响应** (`200 OK`):
```json
[
  {
    "id": "proj_abc123",
    "name": "my-web-app",
    "description": "一个 Node.js Web 应用",
    "status": "running",
    "createdAt": "2026-07-28T08:00:00Z",
    "updatedAt": "2026-07-28T09:30:00Z"
  }
]
```

**错误**:
- `500` — 服务器内部错误

---

### 2. 创建项目

```
POST /projects
```

**请求体**:
```json
{
  "name": "my-web-app",
  "description": "一个 Node.js Web 应用（可选）"
}
```

**响应** (`201 Created`):
```json
{
  "id": "proj_abc123",
  "name": "my-web-app",
  "description": "一个 Node.js Web 应用",
  "status": "idle",
  "createdAt": "2026-07-28T08:00:00Z",
  "updatedAt": "2026-07-28T08:00:00Z"
}
```

**说明**: 创建项目后，后端应自动生成默认的 `Dockerfile` 和 `docker-compose.yaml` 模板文件。

**默认 Dockerfile 模板**:
```dockerfile
FROM alpine:latest

# 设置工作目录
WORKDIR /app

# 复制文件（根据需要修改）
# COPY . .

# 运行命令（根据需要修改）
# CMD ["echo", "Hello World"]
```

**默认 docker-compose.yaml 模板**:
```yaml
version: '3.8'

services:
  app:
    build: .
    # ports:
    #   - "8080:80"
    # volumes:
    #   - ./data:/app/data
    # environment:
    #   - NODE_ENV=production
```

**错误**:
- `400` — 请求参数无效（如名称为空）
- `500` — 服务器内部错误

---

### 3. 获取项目详情

```
GET /projects/{id}
```

**路径参数**:
- `id` — 项目 ID

**响应** (`200 OK`):
```json
{
  "id": "proj_abc123",
  "name": "my-web-app",
  "description": "一个 Node.js Web 应用",
  "status": "running",
  "createdAt": "2026-07-28T08:00:00Z",
  "updatedAt": "2026-07-28T09:30:00Z"
}
```

**错误**:
- `404` — 项目不存在
- `500` — 服务器内部错误

---

### 4. 删除项目

```
DELETE /projects/{id}
```

**路径参数**:
- `id` — 项目 ID

**响应** (`204 No Content` 或 `200 OK`):
```json
{
  "status": "deleted"
}
```

**说明**: 删除项目时应同时删除关联的所有文件（Dockerfile、docker-compose.yaml）。

**错误**:
- `404` — 项目不存在
- `500` — 服务器内部错误

---

### 5. 获取项目文件内容

```
GET /projects/{id}/files/{filename}
```

**路径参数**:
- `id` — 项目 ID
- `filename` — 文件名（`Dockerfile` 或 `docker-compose.yaml`）

**响应** (`200 OK`):
```json
{
  "filename": "Dockerfile",
  "content": "FROM alpine:latest\nWORKDIR /app\nCMD [\"echo\", \"Hello World\"]\n"
}
```

**错误**:
- `404` — 项目不存在或文件不存在
- `500` — 服务器内部错误

---

### 6. 更新项目文件内容

```
PUT /projects/{id}/files/{filename}
```

**路径参数**:
- `id` — 项目 ID
- `filename` — 文件名（`Dockerfile` 或 `docker-compose.yaml`）

**请求体**:
```json
{
  "content": "FROM node:18-alpine\nWORKDIR /app\nCOPY package*.json ./\nRUN npm install\nCOPY . .\nEXPOSE 3000\nCMD [\"node\", \"server.js\"]\n"
}
```

**响应** (`200 OK`):
```json
{
  "filename": "Dockerfile",
  "status": "saved"
}
```

**错误**:
- `400` — 请求参数无效
- `404` — 项目不存在
- `500` — 服务器内部错误

---

### 7. 触发构建

```
POST /projects/{id}/build
```

**路径参数**:
- `id` — 项目 ID

**请求体**: 无

**响应** (`200 OK`):
```json
{
  "buildId": "build_xyz789",
  "status": "started",
  "message": "Build triggered successfully"
}
```

**说明**: 
- 此端点触发 Docker 镜像构建（对项目目录执行 `docker build`）
- 构建过程异步执行，进度通过 WebSocket 端点实时推送
- 项目状态更新为 `building`
- 构建成功后项目状态更新为 `idle`（或根据 compose 状态为 `running`）
- 构建失败后项目状态更新为 `failed`

**错误**:
- `400` — Dockerfile 为空或不存在
- `404` — 项目不存在
- `409` — 项目正在构建中
- `500` — 服务器内部错误

---

### 8. 启动项目（docker-compose up）

```
POST /projects/{id}/up
```

**路径参数**:
- `id` — 项目 ID

**请求体**: 无

**响应** (`200 OK`):
```json
{
  "status": "started",
  "containerIds": ["container_id_1", "container_id_2"],
  "message": "Containers started successfully"
}
```

**说明**:
- 对项目目录执行 `docker-compose up -d`
- 项目状态更新为 `running`
- 需要项目已有 docker-compose.yaml 文件且镜像已构建

**错误**:
- `400` — docker-compose.yaml 为空或不存在
- `404` — 项目不存在
- `409` — 项目正在构建中
- `500` — 启动失败（compose 错误）

---

### 9. 停止项目（docker-compose down）

```
POST /projects/{id}/down
```

**路径参数**:
- `id` — 项目 ID

**请求体**: 无

**响应** (`200 OK`):
```json
{
  "status": "stopped",
  "message": "Containers stopped successfully"
}
```

**说明**:
- 对项目目录执行 `docker-compose down`
- 项目状态更新为 `idle`

**错误**:
- `404` — 项目不存在
- `500` — 停止失败

---

## WebSocket 端点

### 构建日志实时推送

```
WS /ws/projects/{id}/build/logs?api_key={api_key}
```

**连接方式**: WebSocket 直接连接（`ws://` 或 `wss://` 协议）

**路径参数**:
- `id` — 项目 ID

**查询参数**:
- `api_key` — API 认证密钥

**消息格式**（服务端 → 客户端，每条消息一个 JSON 对象）:

```json
// 普通日志行
{
  "stream": "Step 1/5 : FROM node:18-alpine",
  "status": null,
  "error": null,
  "imageId": null,
  "isDone": false
}

// 状态更新
{
  "stream": null,
  "status": "Successfully built abc123def456",
  "error": null,
  "imageId": "abc123def456",
  "isDone": false
}

// 错误
{
  "stream": null,
  "status": null,
  "error": "COPY failed: file not found in build context",
  "imageId": null,
  "isDone": true
}

// 构建完成
{
  "stream": null,
  "status": "Build completed",
  "error": null,
  "imageId": "abc123def456",
  "isDone": true
}
```

**说明**:
- 连接建立后，服务端立即开始推送构建日志
- 每条消息为独立的 JSON 对象，以换行符分隔
- `isDone: true` 表示构建已结束（成功或失败），此时应关闭连接
- 如果构建尚未触发，服务端应等待构建开始后再推送

**错误处理**:
- 如果项目不存在或 build 未触发，服务端应发送一条 error 消息并关闭连接

---

## 认证方式

所有 API 端点均复用现有的认证机制，与 `DockerService` 中其他端点一致：

### HTTP 请求认证头

```
# JWT Token 认证
Authorization: Bearer eyJhbGciOiJIUzI1NiIs...

# API Key 认证
X-API-Key: your-api-key-here
```

### WebSocket 认证

```
ws://host/ws/projects/{id}/build/logs?api_key={your-api-key}
```

---

## 错误响应格式

所有错误响应遵循统一格式：

```json
{
  "detail": "人类可读的错误描述"
}
```

备选字段（后端可使用以下任一字段，前端会自动识别）:
- `detail` — 优先读取
- `message` — 备选
- `error` — 备选
- `msg` — 备选

HTTP 状态码:
- `400` — 请求参数错误
- `404` — 资源不存在
- `409` — 资源状态冲突（如正在构建中）
- `500` — 服务器内部错误
