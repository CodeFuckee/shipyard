---
name: docker-pull-from-file
description: >
  用户给定一个 Dockerfile 或 docker-compose.yml 文件路径，
  自动从中提取所有需要拉取的 Docker 镜像，然后逐个调用 docker-mirror-pull
  技能通过国内镜像源拉取。适用于批量拉取项目所需镜像的场景。
---

# Docker 批量镜像拉取

核心流程：**解析文件 → 提取镜像列表 → 逐个调用 docker-mirror-pull 拉取**。

## 设计原则

- **复用已有技能**：单个镜像的拉取完全委托给 `docker-mirror-pull` 技能，本技能只负责解析文件和编排批量拉取流程。
- **去重**：同一个镜像只拉取一次。
- **容错**：某个镜像拉取失败不中断整体流程，继续拉取下一个，最后汇总报告。
- **智能提取**：自动跳过 `scratch`、纯 `build` 构建（无 `image` 字段）等不需要拉取的镜像。

---

## 工作流程

### 第一步：确认文件路径

从用户消息中提取文件路径：
- 如果用户明确给出了文件路径（如 `./Dockerfile`、`docker-compose.yml`），直接使用
- 如果用户没有给出，在当前工作目录和常见位置搜索：
  - `Dockerfile`、`docker-compose.yml`、`docker-compose.yaml`
  - `**/Dockerfile`、`**/docker-compose.yml`
- 如果找到多个候选文件，列出让用户选择
- 如果找不到任何文件，提示用户提供路径

### 第二步：解析文件提取镜像

#### Dockerfile 解析规则

从 `FROM` 指令中提取镜像：

1. 忽略注释行（以 `#` 开头）
2. 匹配 `FROM` 指令（不区分大小写）：
   - 去掉 `--platform=xxx` 等 flag 参数
   - 去掉 `AS <stage_name>` 别名部分
   - 提取镜像名和 tag
3. 特殊处理：
   - `FROM scratch` → **跳过**，不需要拉取
   - `FROM ${VARIABLE}` → 查找同文件中的 `ARG VARIABLE=value` 或 `ARG VARIABLE`（无默认值时用变量名占位，提醒用户手动指定）
   - `FROM image`（无 tag）→ 保持原样，Docker 默认会使用 `latest`
4. 支持多阶段构建（多个 FROM 指令）

**解析示例**：

| Dockerfile 行 | 提取结果 |
|---|---|
| `FROM nginx:1.25` | `nginx:1.25` |
| `FROM node:20-alpine AS builder` | `node:20-alpine` |
| `FROM --platform=linux/amd64 python:3.12-slim` | `python:3.12-slim` |
| `FROM scratch` | 跳过 |
| `FROM ${BASE_IMAGE}` | 查找 ARG，无默认值则标记为待确认 |
| `FROM ubuntu` | `ubuntu`（默认 latest） |

#### docker-compose.yml 解析规则

从 `services` 下各服务的 `image` 字段提取：

1. 只提取显式声明了 `image:` 的服务
2. 如果服务只有 `build:` 没有 `image:` → **跳过**（本地构建，不需要拉取）
3. 如果服务同时有 `build:` 和 `image:` → **提取 image**（构建后会用该 tag）
4. 支持 YAML 锚点和别名
5. 环境变量占位符（如 `image: nginx:${NGINX_VERSION}`）→ 尝试从同文件或 `.env` 文件解析，无法解析时用变量名占位

**解析示例**：

```yaml
services:
  web:
    image: nginx:1.25          # ✓ 提取
  api:
    build: .                   # ✗ 跳过（无 image）
  db:
    image: postgres:16-alpine  # ✓ 提取
  worker:
    build: .
    image: myapp:local         # ✓ 提取 image
```

### 第三步：整理镜像列表

1. 对提取结果去重（同一个镜像只保留一条）
2. 按字母顺序排列
3. 向用户展示完整列表，简要告知将逐个拉取
4. 如果存在无法解析的变量占位镜像，单独列出并询问用户是否需要处理

### 第四步：逐个拉取镜像

对每个镜像，**调用 `docker-mirror-pull` 技能**进行拉取：

```
/skill docker-mirror-pull
```

传入的提示为镜像名，例如：`帮我拉取 nginx:1.25`

具体方式：使用 `Skill` 工具，`skill` 参数设为 `"docker-mirror-pull"`，`args` 参数设为包含镜像名的拉取指令。

拉取顺序：
1. 先拉取基础/依赖镜像（如 `node`、`python`、`nginx`）
2. 再拉取应用镜像

每个镜像拉取完成后，记录成功/失败状态。

### 第五步：汇总报告

所有镜像拉取完成后，输出汇总：

```
📊 批量拉取结果汇总

✅ 成功 (X/Y):
  - nginx:1.25 → 通过 docker.m.daocloud.io
  - node:20-alpine → 通过 docker.1ms.run
  ...

❌ 失败 (Z/Y):
  - custom-image:latest → 所有镜像源均失败
  ...

💡 提示：
  - 成功拉取的镜像已可用：docker run <镜像名>
  - 如有失败，可手动重试或检查网络
```

---

## 辅助脚本

本技能附带一个 Python 脚本 `extract_images.py`，用于从 Dockerfile 和 docker-compose.yml 中提取镜像列表。**在第二步解析文件时，直接使用该脚本提取，然后再由 AI 做进一步处理（如去重、确认变量等）。**

```bash
python3 ~/.claude/skills/docker-pull-from-file/extract_images.py <文件路径>
```

脚本输出 JSON 格式的镜像列表，每项包含：
- `image`: 镜像名
- `type`: `"fixed"` | `"variable"`（是否含变量占位符）
- `source_line`: 原始行内容

**如果脚本执行出错**（文件格式异常等），回退到 AI 手动解析。

---

## 重要规则

1. **复用技能**：单个镜像拉取必须通过 `docker-mirror-pull` 技能完成，不要直接调用 `pull.py` 或 `docker pull`
2. **不要中断**：某个镜像失败后继续下一个，不要提前终止
3. **用户确认**：拉取前向用户展示镜像列表，但无需逐个确认每个镜像的拉取
4. **记录中间结果**：每拉完一个镜像就报告一次进度，让用户看到实时状态
5. **特殊镜像警告**：如果检测到 `mysql`、`postgres` 等数据库镜像，提醒用户注意数据持久化配置

---

## 示例交互

用户输入：
```
帮我从这个项目的 Dockerfile 和 docker-compose.yml 拉取所有镜像
```

技能执行：
1. 在当前目录找到 `Dockerfile` 和 `docker-compose.yml`
2. 运行 `extract_images.py` 提取镜像 → 得到 `["node:20-alpine", "nginx:1.25", "postgres:16-alpine", "redis:7-alpine"]`
3. 展示列表，告知用户将逐个拉取
4. 调用 `docker-mirror-pull` 拉取 `node:20-alpine` → 成功
5. 调用 `docker-mirror-pull` 拉取 `nginx:1.25` → 成功
6. 调用 `docker-mirror-pull` 拉取 `postgres:16-alpine` → 成功
7. 调用 `docker-mirror-pull` 拉取 `redis:7-alpine` → 成功
8. 汇总报告：4/4 全部成功
