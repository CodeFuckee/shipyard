# hermes-agent 部署与接入指南（issue #25）

Shipyard 的 AI 助手在启用 Hermes 接入后，由 [hermes-agent](https://github.com/NousResearch/hermes-agent)
（NousResearch 的 AI Agent）负责完整的工具调用循环：LLM 推理、MCP 工具集
（shipyard 的 33 个 Docker 管理工具 + 2 个镜像拉取 skill 工具）调度与执行
都在 hermes-agent 侧完成，shipyard 后端只透传对话请求。

hermes-agent 可部署在 shipyard 同一台服务器上（推荐以容器随 shipyard
一并部署，即容器内集成），也可部署在**其他设备**（内网主机 / VPS 等），
只要 shipyard 后端能通过 HTTP 访问它即可；接入地址统一通过部署环境的
`HERMES_BASE_URL` 环境变量下发（issue #33 起前端设置页不再提供配置）。

## 1. 部署 hermes-agent

### 方式 A：官方 Docker 镜像（推荐）

```bash
# 1. 创建数据目录（配置 / API Key / 会话都保存在这里）
mkdir -p ~/.hermes

# 2. 首次运行安装向导，配置 LLM 供应商（OpenRouter 等）
docker run -it --rm -v ~/.hermes:/opt/data nousresearch/hermes-agent setup

# 3. 以后台网关模式运行，开启 OpenAI 兼容 API Server（端口 8642）
#    API_SERVER_KEY 用 openssl rand -hex 32 生成，shipyard 侧填同一个值
docker run -d \
  --name hermes \
  --restart unless-stopped \
  -v ~/.hermes:/opt/data \
  -p 8642:8642 \
  -e API_SERVER_ENABLED=true \
  -e API_SERVER_HOST=0.0.0.0 \
  -e API_SERVER_KEY="<生成的密钥>" \
  nousresearch/hermes-agent gateway run
```

> 安全提示：API Server 对公网开放有风险（hermes 自带终端等工具）。
> 内网部署请限制在局域网；公网部署请置于防火墙 / 反向代理之后，
> 且 API_SERVER_KEY 必填并足够长。

### 方式 B：源码安装（无 Docker 时）

hermes-agent **不发布 pip 包**，需克隆源码并安装依赖：

```bash
# 需要 uv（Python 包管理器）
curl -LsSf https://astral.sh/uv/install.sh | sh

git clone https://github.com/NousResearch/hermes-agent.git ~/.hermes/hermes-agent
cd ~/.hermes/hermes-agent
uv sync

# 配置 LLM 供应商（见下节），然后启动网关 + API Server
uv run hermes gateway
```

## 2. 配置 LLM 供应商

hermes-agent 的模型配置位于 `~/.hermes/`（容器方式则直接编辑宿主机该目录）：

- **OpenRouter**（推荐，无需自建端点）：在 `~/.hermes/.env` 写入

  ```bash
  OPENROUTER_API_KEY=sk-or-v1-xxxx
  # 可选：默认模型
  HERMES_MODEL=openrouter/auto
  ```

- **任意 OpenAI 兼容端点**（自建 vLLM / Ollama / One API 等）：

  ```bash
  # ~/.hermes/.env
  OPENAI_API_KEY=<端点的 Key>
  OPENAI_BASE_URL=http://<端点地址>/v1   # 仅 openai-api provider 生效
  ```

  完整供应商列表与配置见
  <https://hermes-agent.nousresearch.com/docs/integrations/providers>。

配置完成后在容器 / 源码目录内运行 `hermes model` 可查看并切换模型；
`hermes chat` 可先验证对话正常。

## 3. 接入 shipyard 的 MCP 工具（35 个）

hermes-agent 通过 MCP 连接 shipyard 后端，把 Docker 管理工具注册为
自己的工具集。在 `~/.hermes/config.yaml` 增加：

```yaml
mcp_servers:
  shipyard:
    url: "http://<shipyard-host>:8000/mcp"
    headers:
      Authorization: "Bearer <shipyard API Key>"
```

- `<shipyard-host>`：shipyard 后端地址（hermes 容器内访问宿主机用
  局域网 IP 或 `host.docker.internal`，视网络模式而定）
- `<shipyard API Key>`：shipyard 的 API Key（设置页生成），MCP 端点
  直接接受 Bearer API Key（无需 OAuth 流程）

启动后可用 `hermes mcp test shipyard` 或 `/reload-mcp` 验证；
工具共 35 个（33 个 Docker 管理 + docker_mirror_pull /
docker_pull_from_file 两个镜像拉取 skill 工具）。

## 4. shipyard 侧配置

shipyard 只调用部署环境配置的 hermes（issue #33 起不再支持前端设置页
配置外部 hermes，配置随部署通过环境变量下发）：

| 环境变量 | 值 |
|------|-----|
| `HERMES_BASE_URL` | `http://<hermes-host>:8642/v1` |
| `HERMES_API_KEY` | 第 1 步生成的 `API_SERVER_KEY` |
| `HERMES_MODEL` | 留空（使用 hermes 侧默认模型），或填 hermes 配置的模型名 |

`HERMES_BASE_URL` 为空时 Hermes 接入未启用，AI 聊天回退 AI 供应商
默认供应商；两者都不可用时返回 503（error_code=llm_not_configured）。
启用后 AI 聊天由 hermes-agent 完成工具调用循环，流式回复中的工具
执行步骤照常显示在聊天界面。

## 5. 故障排查

| 现象 | 排查 |
|------|------|
| 对话 401/403（hermes 拒绝） | `HERMES_API_KEY` 与 hermes 的 `API_SERVER_KEY` 不一致 |
| 对话 404 | `HERMES_BASE_URL` 缺少 `/v1` 前缀，或 hermes 未开启 `API_SERVER_ENABLED` |
| 对话连接超时 | 网络不通 / 端口未映射（容器方式需 `-p 8642:8642`）/ `API_SERVER_HOST` 未设为 `0.0.0.0` |
| 对话无工具步骤 | `~/.hermes/config.yaml` 未配置 `mcp_servers.shipyard`，或 shipyard 地址在 hermes 侧不可达 |
| hermes 报模型错误 | `~/.hermes/.env` 未配置 LLM 供应商 Key，`hermes chat` 先验证 |
