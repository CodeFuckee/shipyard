# Changelog

所有重要变更均记录在此文件。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Fixed

- 修复后端启动崩溃（流水线 #535 部署失败）：`main.py` lifespan 中
  `with SessionLocal() as db:` 依赖 SQLAlchemy 1.4+ 的 Session 上下文管理器
  协议，而 pip 构建时镜像源网络抖动会回溯装到 1.3.x（实测 NAS 装到
  sqlalchemy-1.3.24）导致 `TypeError: 'Session' object does not support
  the context manager protocol`，uvicorn 启动即退出、健康检查 502。
  修复：改用 `try/finally` 兼容写法；requirements.txt 锁定
  `sqlalchemy>=2.0,<3.0`（项目代码使用 2.x API，如 `Session.get`），
  防止构建回溯安装旧版本。

### Added

- AI 供应商默认模型改为下拉选择（issue #16 续作）：编辑供应商表单打开时
  自动通过 OpenAI 兼容 `{base_url}/models` 接口拉取模型列表（后端代理），
  默认模型字段由文本输入改为下拉选择——显示模型名称，选中即保存；当前
  默认模型不在列表中时以「（当前）」作为首项保留避免丢失；拉取失败提示
  原因并可重试、列表为空时回退手动输入兜底；新增模式保持手动输入（供
  应商创建后才可拉取）。新增 7 个 widget 测试
  （`test/ai_providers_screen_test.dart`）。
- 镜像拉取 Agent（issue #15，基于 langchain 实现，使用 backend/skills
  的两个 skill 拉取镜像）：
  - 后端新增 `app/agent/` 模块：`mirror_sources.py`（镜像源列表，环境
    变量 `AGENT_MIRROR_PREFIXES` 逗号分隔覆盖默认兜底 7 个国内镜像源）、
    `executor.py`（拉取执行器，docker SDK 连接 Docker Unix socket 执行
    `images.pull` 与打标签，线程池超时保护，无需 sudo / docker CLI）、
    `tools.py`（langchain 工具 `docker_mirror_pull` 单镜像多源逐个尝试
    成功即停、`docker_pull_from_file` 调用 extract_images.py 解析
    Dockerfile / docker-compose 批量拉取 + 去重 + 变量占位标注，镜像名
    正则防注入校验）、`service.py`（langchain `create_agent` 构建
    ReAct agent，LLM 复用 hermes 接入配置，model 未配置时自动探测
    `{base}/models` 首个可用模型）。
  - 后端 `app/routers/agent.py`（`/admin/agent` 前缀，X-API-Key 保护，
    nginx 复用现有 `location /admin` 代理）：`GET /status`（LLM 配置 +
    工具列表 + 生效镜像源）、`POST /chat`（非流式对话，返回最终回复与
    工具执行步骤；未配置 hermes 503、上游错误 502；消息与
    max_iterations 校验 422）。
  - 配置项：`AGENT_MIRROR_PREFIXES` / `AGENT_MAX_ITERATIONS`（默认 10）/
    `AGENT_PULL_TIMEOUT`（默认 600s）；依赖新增 langchain、
    langchain-openai。
  - 新增测试 45 个：`tests/test_agent_tools.py`（33：镜像名校验参数化、
    多源切换成功/全失败、自定义源、批量拉取/去重/变量标注、解析脚本
    真实调用与异常、镜像源环境变量覆盖）、`tests/test_agent_api.py`
    （12：认证 401、未配置 503、422 校验、502 透传、status 字段）。
- Hermes 接入（issue #14，后端接入其他设备上部署的 hermes 实例）：
  - 后端 `app/services/hermes_client.py`：OpenAI 兼容客户端（httpx），
    环境变量配置 `HERMES_BASE_URL`（空 = 未启用）/ `HERMES_API_KEY`
    （可选）/ `HERMES_MODEL`（可选默认模型）；状态查询、连接测试
    （`{base}/models`，超时 30s，401/403 → Key 无效、404 → 提示补
    `/v1`）、非流式对话（`{base}/chat/completions`）、SSE 流式对话
    （逐 chunk 产出 delta 事件，容错跳过杂行/坏 JSON，上游错误转
    error 事件而非中断）。
  - 后端 `app/routers/hermes.py`（`/admin/hermes` 前缀，X-API-Key
    保护，nginx 复用现有 `location /admin` 代理）：`GET /status`
    （配置状态 + 连接测试，任何响应不含 Key 明文）、`POST /chat`
    （非流式，未配置 503、上游错误 502）、`POST /chat/stream`
    （SSE，事件 `{type: delta|done|error}`）；消息校验（合法 role、
    必填 content，非法 422）。
  - 前端 `hermes_config_screen.dart`：设置页新增"Hermes 接入"入口，
    只读展示接入状态（启用/未配置、实例地址、默认模型、Key 配置
    状态）与测试连接结果，测试连接按钮 + 下拉刷新；ARB 新增 17 条
    文案（中英）。
  - 新增测试 43 个：`tests/test_hermes_client.py`（29：正常路径 +
    未配置/超时/无法连接/401/403/404/500、base_url 规范化、流式
    SSE 解析与容错、无 [DONE] 正常结束）、`tests/test_hermes_api.py`
    （14：认证 401、未配置 503、422 校验、502 透传、SSE 输出、Key
    永不回显）。
  - 追加需求（前端设置配置）：`PUT /admin/hermes/config` 保存接入
    配置（前端设置页，数据库持久化，Key 经 crypto.encrypt 加密存储）；
    `hermes_config` 表（单行 id=1）+ `app/services/hermes_config.py`
    存取服务；配置优先级：前端保存值 > 环境变量（`/status` 新增
    `source` 字段标识来源），保存后即时同步运行时无需重启，应用启动
    时从数据库加载；前端 `hermes_config_screen.dart` 新增"编辑配置"
    表单（实例地址/API Key/默认模型，Key 留空不修改，地址清空 = 禁用
    接入），保存后自动刷新状态并测试连接；ARB 新增 11 条文案（中英）。
  - 追加测试 8 个（`tests/test_hermes_api.py`）：保存配置认证 401、
    正常保存（URL 规范化、Key 加密存储、响应不回显、source=database）、
    空 Key 保留原值、空地址禁用、非法 URL 422、保存后 /status 生效、
    环境变量回落与数据库覆盖。
- AI API 供应商配置（设置页入口，纯配置存储，为后续 AI 功能做准备）：
  - 后端 `app/routers/ai_providers.py`（`/admin/ai-providers` 前缀）：
    供应商增删改查（GET/POST/PUT/DELETE，名称唯一、重名 409）、
    API Key 经 `crypto.encrypt` 加密存储（任何响应不返回明文，
    仅返回 `api_key_configured` 标记）、`POST /{id}/test` 测试连接
    （httpx 请求 OpenAI 兼容 `{base_url}/models` 端点，Bearer 认证，
    10s 超时；401/403 → Key 无效、404 → Base URL 错误、连接失败/
    超时分别给出可读原因）。
  - 数据模型 `AIProviderModel`（`ai_providers` 表）：name（唯一）、
    provider_type（deepseek/openai/custom）、base_url、加密 Key、
    默认模型、启用开关、时间戳。
  - 前端 `ai_providers_screen.dart`：供应商列表（类型徽章/Key 配置
    状态/启用状态）、添加/编辑表单对话框（deepseek/openai 预设自动
    填充 Base URL 与默认模型；编辑时 Key 留空不修改）、测试连接、
    删除确认；操作菜单按平台规则（手机端底部菜单 / 其他端居中
    对话框）；设置页新增"AI 供应商配置"入口；ARB 新增 28 条文案。
  - 新增测试 40 个：后端 `tests/test_ai_providers.py`（26：CRUD 正常
    路径、空名称/重名/非法 URL/缺 Key 边界、更新保留 Key、删除/更新
    不存在 404、Key 永不回显、数据库加密存储、测试连接成功/401/网络
    错误/超时）；前端 `test/ai_providers_screen_test.dart`（14：列表
    渲染、空态/错误态、添加表单校验与 POST、预设填充、编辑 PUT 且
    Key 留空不携带、删除 DELETE、测试连接成功/失败）。
- AI 供应商通过 API 获取模型列表（issue #16，配置模型不再需要手动
  输入，改为从 OpenAI 兼容 `{base_url}/models` 端点拉取后选择）：
  - 后端 `GET /admin/ai-providers/{id}/models`：代理请求
    `{base_url}/models`，解析 `data` 数组返回
    `{"ok": true, "models": [{"id": "...", "name": "..."}]}`；失败时
    `{"ok": false, "message": "..."}`（无 Key/超时/无法连接/401/403/
    404/非法 JSON/结构异常），HTTP 状态始终 200（与测试连接一致）；
    模型项缺 name 用 id 兜底，data 中非 dict/无 id 项跳过。错误处理
    逻辑与测试连接共用提取的 `_request_models()`（行为不变）。
  - 前端编辑供应商表单新增"获取模型列表"按钮（仅编辑模式，供应商
    已创建才有 id 可查）：点击后经后端拉取模型列表，弹窗展示并选择
    回填默认模型；失败展示后端原因、空列表提示可手动输入；新增模式
    保持手动输入（创建后再编辑即可拉取）。ARB 新增 5 条文案（中英）。
  - 新增测试 19 个：后端 `tests/test_ai_providers.py`（15：成功解析、
    name 兜底、跳过非法项、空列表、缺 data 字段、非对象响应、非法
    JSON、无 Key、401、404、超时、网络错误、供应商不存在 404、认证
    401、使用更新后存储 Key）；前端 `test/ai_providers_screen_test.dart`
    （4：获取模型列表弹窗选择回填、失败提示且不改模型、空列表提示、
    新增模式无按钮）。
- 容器升级功能（容器列表页与详情页"升级"按钮，仅更新镜像版本，
  端口/挂载/环境变量等参数保持不变）：
  - 后端 `POST /containers/{id}/check-update`：docker pull 增量拉取最新
    镜像（幂等）后对比容器创建时镜像 Id（`ImageID`）与最新镜像 Id 的
    digest，返回 `update_available` / `up_to_date` / `unknown` 三态；
    digest 缺失时回退 `RepoDigests` 对比。
  - 后端 `POST /containers/{id}/upgrade`：pull → 临时名创建新容器
    （创建失败则旧容器保持原样）→ 停止并删除旧容器（保留卷）→
    新容器改回原名 → 启动。重建参数从容器 attrs 提取：环境变量、端口
    绑定（含 HostIp/随机端口/仅 expose）、挂载（含 ro 标志）、重启策略、
    labels、自定义网络（别名/固定 IP）、healthcheck、devices/cap、
    资源限制等；`container:` 网络模式（依赖其他容器）拒绝升级。
  - 前端 `handleContainerUpgrade` 共用流程（`utils/container_upgrade.dart`）：
    检查更新 loading → 结果对话框（有更新显示新旧 digest 摘要；无法对比
    digest 时仍可确认尝试）→ 确认后执行升级并提示结果；两个 ARB 新增
    11 条文案。
  - 新增测试 43 个：后端 `tests/test_container_update.py`（33：
    digest 对比三态、pull 失败、attrs 重建参数、container: 网络拒绝、
    API 层 200/500/401）；前端 `test/container_upgrade_test.dart`（10：
    服务层请求行为 + 升级对话框全流程）。
- 生产环境写操作测试的备份/恢复保护（frontend/selenium_tests_prod）：
  - 新增 `backup_restore.py`：通过后端备份/恢复 API（POST /backups、
    POST /backups/{filename}/restore?confirm=true）实现"测试前备份、
    测试后恢复"。API key 经 `TEST_API_KEY` 环境变量注入，支持按主机
    覆盖 `TEST_API_KEY_<host>`（与登录凭据约定一致）。
  - 新增 module 级 fixture `prod_backup_restore`（conftest.py）：
    网页授权添加服务器测试（test_prod_connect.py）模块开始前对
    源/目标服务器各创建一次备份，模块结束后（无论测试成败）恢复，
    恢复后等待后端服务重启完成（Docker restart policy 拉起）。
    恢复失败时测试报错，避免生产环境残留测试引入的状态。
    未配置 API key 时打印警告并降级为不保护（现有用法不受影响）。
  - test_prod_connect.py 通过 `pytestmark = usefixtures("prod_backup_restore")`
    挂接保护；新增离线单元测试 `tests/test_backup_restore_util.py`
    （21 用例：per-host key 解析、备份/恢复 URL 与参数、文件名
    合法性校验防路径穿越、服务恢复等待超时等）。
  - 移动端（Android/iOS/鸿蒙）网页授权添加服务器（/connect 流程，
  与 Web 端共享协议、后端零改动）：
  - 深链基建：新增 `app_links`（Android/iOS/桌面）与 `crypto`（io 端
    SHA-256）；鸿蒙在 `huawei/` 工程声明 `shipyard://` scheme
    （module.json5 skills uris），`EntryAbility` 冷启动（onCreate）/
    热启动（onNewWant）捕获深链入队，`HarmonyPlatformPlugin` 新增
    `getInitialDeepLink`/`consumeDeepLink` 通道方法。
  - `ConnectService` 平台化：`connect_platform_io.dart` 从抛错 stub 改为
    完整实现（url_launcher/HarmonyosPlatform 跳转、纯 Dart SHA-256、
    PreferencesService 存储）；`buildRedirectUri()` 移动端返回
    `shipyard://connect/callback`；`probe()` 去掉 kIsWeb 保护。
  - 回跳处理：冷启动在 `main()` runApp 前消费 `initialLink()`；
    热启动由 `_MyAppState` 生命周期监听在 app 恢复时消费
    `pendingLink()`，token 交换期间显示加载对话框（防重入）。
  - 设置页"网页授权添加"入口对移动端开放（桌面端保持隐藏），
    探测成功卡片增加"将打开系统浏览器"提示。
  - `_addServerFromConnect` 改用 `PreferencesService`，修复鸿蒙上
    SharedPreferences 不可用的问题。
  - 新增测试 24 个：`connect_platform_io_test.dart`（8）、
    `connect_service_mobile_test.dart`（15）、
    `settings_connect_mobile_flow_test.dart`（1）。
  - 文档 `docs/connect-flow-mobile.md` 标记已实现，补充 Android/iOS
    宿主工程（仓库外）的 scheme 声明说明。
- 新增前后端 VSCode 调试配置（`.vscode/`）：
  - `launch.json`：后端 FastAPI（debugpy + uvicorn，`main:app` 端口 8000）与
    pytest 调试；前端 Flutter（Chrome / Web Server :8080）调试；compound
    「前后端联调」一键同时启动前后端。
  - `tasks.json`：后端依赖安装（含 debugpy 自动补装）、dev.sh 启动、pytest
    全量测试；前端 `flutter pub get` / `flutter test` / `flutter analyze` /
    `flutter run -d chrome`。
  - `settings.json`：Python 解释器指向 `backend/.venv/bin/python`、启用
    pytest 测试发现、排除 build/data 等目录。
  - `extensions.json`：推荐 Python / debugpy / Flutter 插件。
- 生产环境首帧加载速度测试（`frontend/selenium_tests_prod`）：
  - 新增 `tests/test_prod_first_frame.py`：测量每个生产环境从发起导航到
    首帧渲染完成（flutter-view 出现且语义树有内容）的耗时，每环境参数化；
    WASM 加载失败自动刷新重试（最多 3 次，耗时按最后导航重新计时）。
  - 加载时间输出到最终测试结果：pytest-html extra 注入 `report.html`，
    `[首帧] <url>: <耗时>` 汇总行进入 `pytest_output.log`（`run_tests.sh`
    默认加 `-s`）。
  - 新增 `tests/test_first_frame_util.py`（7 用例：正常路径/WASM 重试计时/
    持续失败上限/非 WASM 失败不重试/刷新异常终止/自定义重试上限/URL 参数
    去重），fake driver 离线运行，覆盖测量逻辑边界。
- 新增备份与恢复前端页面（设置页 →「备份与恢复」）：
  - 手动创建备份、备份列表（文件名/大小/时间）、下载备份到本地
    （Web 浏览器下载，手机/桌面保存到下载目录）、删除备份（确认弹窗）。
  - 恢复备份：危险操作需在确认弹窗中输入 `RESTORE` 才可执行
    （覆盖数据库并重启服务，前端提示重新连接）。
  - 定时备份配置：启用开关 + 简单模式（每天执行时间选择 + 保留天数）与
    高级模式（直接编辑 5 段 cron 表达式）可切换，展示下次备份时间。
  - 新增前端测试 `frontend/test/backup_screen_test.dart`（20 用例：页面渲染、
    创建/恢复（输入校验与取消）/删除/下载、定时配置简单与高级模式、错误路径）。
- 后端备份 API 扩展：
  - 新增 `GET /backups/{filename}/download` 下载端点（文件名校验防路径穿越）。
  - 新增 `GET/PUT /backups/schedule` 定时备份配置端点：配置持久化到
    `BACKUP_SCHEDULE_FILE`（默认 `data/backup_schedule.json`，优先于环境变量），
    调度线程每次循环重读，修改立即生效、无需重启；校验非法 cron / keep_days 越界。
  - 新增后端测试 `backend/tests/test_backup_schedule.py`（25 用例：配置默认值/
    文件优先/损坏容错/校验/持久化/幂等/端点 400/422）与下载端点测试（5 用例）。
- 新增备份与恢复功能（后端 `backend/app/routers/backups.py` + `services/backup_service.py`）：
  - `POST /backups` 手动创建备份：SQLite 数据库经 sqlite3 backup API 在线导出，
    打包为 tar.gz（keys.db + meta.json）并用 SECRET_KEY 派生密钥整体加密，
    存储于服务器本地目录（`BACKUP_DIR`，默认 `data/backups/`）。
  - `GET /backups` 备份列表；`DELETE /backups/{filename}` 手动删除（按天保留，
    `BACKUP_KEEP_DAYS` 自动清理）。
  - `POST /backups/{filename}/restore?confirm=true` 恢复：覆盖现有数据库，
    恢复前自动生成 `pre_restore` 快照，替换后进程自动重启
    （Docker `restart: unless-stopped` 拉起加载新库）。
  - 定时备份：`BACKUP_CRON` 环境变量（标准 5 段 cron，自实现解析器
    `services/backup_scheduler.py`，无新依赖）。
  - 新增测试 `backend/tests/test_backups.py`（63 用例：加密往返/篡改/截断/
    错误密钥、cron 解析与 10 种非法表达式、备份/清理/恢复边界、
    REST 端点与路径穿越防护）。
- 项目列表页新增显式删除入口：每个项目卡片右上角增加删除图标，点击弹出确认对话框，
  确认后调用 `DELETE /projects/{id}` 删除项目（同时执行 `docker compose down` 停止容器、
  删除数据库记录、清理服务器上项目文件夹），删除成功后列表自动刷新；
  移除原长按卡片触发的删除交互，统一为显式操作。
- 新增后端项目删除测试 `backend/tests/test_projects_delete.py`（11 用例）：
  正常删除（记录+文件夹）、404、409（构建中禁止删除）、compose down 调用与跳过、
  文件夹缺失/删除失败容错、无认证 401；
  新增前端删除交互测试 `frontend/test/projects_delete_test.dart`（5 用例）：
  图标显示、确认对话框、确认发送 DELETE 请求并刷新、取消不请求、长按不再触发。

### Fixed

- 修复代码编辑器 Dockerfile 语法高亮吞掉空格（issue #13：Dockerfile 未
  正确显示空格）。根因：`_highlightDockerfileValue` 用 `\S+` 正则切分
  高亮 token，未被匹配的空白字符（参数间空格、行首缩进、多空格对齐）没有
  生成对应的 `TextSpan`，导致渲染文本丢失空格（如 `RUN apt-get update`
  显示为 `RUNapt-getupdate`）。修复：遍历正则匹配时保留相邻未匹配区间
  原文（`lastEnd` 游标补齐空格），引号字符串与普通 token 高亮不变。
  新增 `test/code_editor_spaces_test.dart` 共 7 个测试（指令参数空格、
  单空格参数、延续行缩进、多空格对齐、引号/CMD 参数、注释/普通行、
  YAML 高亮回归），全量 177 个前端测试通过。
- 修复生产环境写操作测试的备份/恢复保护实际未生效（issue 反馈：测试后
  507 服务器列表多一个服务器、508 密钥列表多一个密钥，恢复未回到测试前
  状态）。三重根因与修复：
  - **保护从未启用**：备份/恢复客户端 `backup_restore.py` 仅支持
    `X-API-Key` 认证，而 CI 未配置 `TEST_API_KEY`，`prod_backup_restore`
    fixture 降级为"警告后裸跑"写操作测试，测试残留无法恢复。修复：
    认证双通道对齐后端 `get_api_key`——新增 `X-Admin-User + X-Admin-Pass`
    通道（复用 `TEST_USERNAME/TEST_PASSWORD` 及按主机覆盖变体，CI 已配置），
    `backup_restore_targets` 任一通道可用即启用保护。
  - **恢复请求返回 502**：后端 `restore_backup` 在响应写出前调用
    `os._exit(1)` 杀进程（nginx 前置部署实测客户端收到 502）。修复：
    端点返回带 `background`（`BackgroundTask(restart_process)`）的响应，
    响应发送后才触发进程退出（`response: Response` 参数上设置的 background
    不会被 FastAPI 迁移，实测无效，故直接构造返回）。
  - **恢复后服务无法启动**（实测恢复后 507/508 后端持续不可用，nginx
    存活但上游 502/超时，直到容器重建）：uvicorn `--reload` 模式下容器
    主进程是 reloader，其 `run()` 只等待文件变化才重启 worker
    （uvicorn 0.52 `supervisors/basereload.py`），worker 自行
    `os._exit(1)` 后 reloader 毫无察觉、不会拉起新 worker，Docker
    restart policy 也不触发（容器主进程活着）。修复：`restart_process`
    先 SIGKILL reloader 父进程（容器主进程退出 → Docker 拉起全新容器
    加载新库），`os._exit(1)` 兜底（无 `--reload` 部署时 worker 即
    容器主进程，直接退出即触发重启）；本地 uvicorn `--reload` 实测
    worker 杀 reloader 后整个进程树退出、端口释放。
    附带修复：数据库替换后清理残留的 `keys.db-wal / keys.db-shm`
    （旧 inode 与新主文件不匹配）；恢复等待探测改测 FastAPI `/docs`
    端点并把 502/503/504（nginx 上游错误）视为未恢复（原探测 `/`
    在 nginx 前置部署下恒 200 误判已恢复）。
  - 安全加固：源/目标环境均无可用认证或备份失败时，写操作测试
    `pytest.skip` 而非裸跑（禁止无保护写生产环境）；恢复等待超时放宽至 180s。
  - 测试：前端 `test_backup_restore_util.py` 新增 Admin 凭据解析/认证头
    选择/上游错误判定等 12 用例（34 个全部通过）；后端 `test_backups.py`
    新增 `restart=False` 不重启与 WAL/SHM 清理 2 用例（70 个全部通过）。

- 修复 Web 端下载备份一直提示"下载失败"（后端 `GET /backups/{filename}/download`
  返回 200 正常，前端仍失败）：`frontend/lib/utils/file_helper_web.dart` 中
  `_JSBlob` extension type 的外部构造器缺少 `@JS('Blob')` 注解，dart2js 编译后
  调用 JS 中不存在的 `_JSBlob` 构造函数，浏览器运行时抛
  `TypeError: _JSBlob is not a constructor`，`triggerDownload` 失败被页面 catch
  后提示"下载失败"（Web 端容器文件下载同样受影响，移动端不受影响）。
  修复：为 `_JSBlob` 构造器补充 `@JS('Blob')` 注解。新增复现测试
  `frontend/test/file_helper_web_js_annotation_test.dart`（源码断言锚定注解缺失）；
  真实浏览器 + 本地后端端到端验证：修复前报错、修复后下载成功且 Blob 内容
  与后端备份文件校验和一致。

- 修复备份与恢复页面加载报错 `FormatException: SyntaxError: Unexpected token '<',
  "<!DOCTYPE" ... is not valid JSON`：`frontend/nginx.conf` 缺少 `/backups` 反向代理
  location，备份页面请求 `GET /backups`、`GET /backups/schedule` 被 `location /`
  （SPA 回退）捕获，nginx 返回 Flutter `index.html`（HTML 而非 JSON），前端
  `jsonDecode` 解析失败。修复：nginx.conf 新增 `location /backups` 代理到后端。
  测试改进：`backend/tests/test_nginx_config.py` 原手工维护的 `KNOWN_API_PREFIXES`
  前缀列表改为从后端 `main.app` 自动提取全部 API 前缀（递归展开 FastAPI 新版
  `_IncludedRouter` 占位路由），并新增 `/backups` 复现测试，杜绝未来新增 router
  再遗漏 nginx 代理。

- 修复使用 git URL 创建项目时未识别仓库自带的 `docker-compose.yml`（`.yml` 扩展名）
  而补写默认 `docker-compose.yaml` 模板：`create_project`（REST + MCP）原来只检查
  `docker-compose.yaml` 一个文件名，导致仓库自带的 compose 编排文件被无视、多余生成
  默认模板。修复：新增 `resolve_compose_file()` 按优先级解析四种 compose 标准命名
  （`docker-compose.yaml` → `docker-compose.yml` → `compose.yaml` → `compose.yml`），
  应用于创建补模板、`up`/`down`/`delete` 容器操作，文件读写 API 对前端固定请求的
  `docker-compose.yaml` 透明映射到项目实际使用的 compose 文件（前端零改动）。
  涉及 `backend/app/routers/projects.py`、`backend/app/mcp/tools.py`；新增回归测试
  `backend/tests/test_projects_git_clone.py`（REST + MCP 各 1 用例）。
- 修复 `frontend/selenium_tests_prod` 生产 connect 测试连续失败（流水线 430/434）：
  CI 容器 Chromium 默认英文 locale 渲染 Flutter 英文 UI，而 `pages/settings_page.py`
  的 XPath 定位全用中文字符串（"添加服务器"/"服务器列表"/"网页授权添加"/"继续"/"确认"），
  在英文页面上全部失配，`click_add_server` 重试后抛 `AssertionError: 多次尝试后仍未弹出添加服务器菜单`。
  修复：① `conftest.py` 给 Chrome/Firefox 强制 `--lang=zh-CN` + `intl.accept_languages=zh-CN,zh,en`；
  ② `settings_page.py` 全部定位 XPath 改为中英文双匹配（Add Server/Servers/Authorize Add/
  Continue/Confirm/does not support authorized adding），并提取 `SERVER_LIST_CONTAINER`、
  `EMPTY_STATE_BTN` 常量。新增静态 XPath 求值回归测试 `tests/test_locale_matching.py`
  （lxml，18 用例，中英文双 UI 覆盖）；`requirements.txt` 增加 lxml 依赖。
- 修复 `frontend/selenium_tests_prod/run_tests.sh` 依赖安装逻辑：原条件仅在
  `import selenium` 失败时才安装 requirements，而 CI 构建目录的 venv 跨 job 持久化复用，
  requirements 新增依赖永远不会被装上（流水线 435 因此报 `ModuleNotFoundError: No module named 'lxml'`）。
  改为每次运行增量 `pip install -r requirements.txt`（已装包秒级跳过，无网络开销）。
- 修复 `frontend/selenium_tests_prod` connect 测试最后一步失败（`服务器列表未出现
  目标服务器`）：前端 `_maskUrl` 对服务器 URL 主机名打码显示（>5 字符时 前3+****+后2，
  如 `127.0.0.1 → 127****.1`、`10.0.0.122 → 10.****22`），而测试 `server_list_contains`
  / `current_server_host` 用完整主机名匹配页面文本，必然失败（locale 修复让授权流程
  首次走通后才暴露）。修复：抽取 `masked_host` / `text_contains_host` 纯函数与前端打码
  格式对齐，`server_list_contains` 兼容打码与完整两种形式，connect 断言允许打码主机名；
  新增回归测试 `tests/test_host_matching.py`（10 用例）。
- 修复 `frontend/selenium_tests_prod/https_proxy.py` 转发时自动跟随 302 破坏授权回跳
  （connect 测试最终根因）：`urllib.request.urlopen` 的 HTTPRedirectHandler 默认跟随
  302，confirm 的 302 回跳（Location 指向源服务器 /connect/callback）被代理自己消费，
  浏览器收到跟随后的页面，授权流程中断（流水线 441 诊断：confirm 后页面停在代理
  地址的登录页、源服务器无 /connect/callback 记录）。修复：抽取 `_open_request` 使用
  NoRedirect opener（3xx 原样透传，HTTPError 作为响应返回）；新增回归测试
  `tests/test_proxy_redirect.py`（2 用例，本地 302 服务器验证不跟随）。
- 优化 Flutter Web 首帧加载速度（首次打开 canvaskit.wasm 加载耗时 30 秒 → 预计
  ~5-10 秒）：根因是本地 canvaskit.wasm（7MB）未压缩传输 + 关键路径串行下载
  （`nginx.conf` 的 `gzip_types` 缺 `application/wasm`，实测 gzip -9 后仅 ~2.8MB、
  -60%；`web/index.html` 无 preload，wasm 要等 main.dart.js 执行后才开始下载）。
  修复（方案 D）：
  - CI `frontend:build_web` 改用 `flutter build web --wasm`（dart2wasm + skwasm，
    skwasm.wasm 3.4MB 替代 canvaskit 7MB，-50%；产物含 dart2js+canvaskit 双 build，
    不支持 WasmGC 的老浏览器自动降级，不白屏）；ohos 分支 SDK 缺 wasm-opt 工具，
    build job 增加 binaryen 120（Debian sid 源）幂等安装 + LD_LIBRARY_PATH。
  - `nginx.conf`：`gzip_types` 增加 `application/wasm`、`gzip_comp_level 6`、
    `gzip_static on`（命中 Dockerfile 预压缩 .gz 时零 CPU 开销）。
  - `web/index.html`：新增与 flutter loader 决策一致（WasmGC/ImageCodecs/blink UA）
    的动态 `<link rel="preload">`，wasm 与 main.dart.js 并行下载。
  - `Dockerfile.cn` / `Dockerfile.gpu.cn` / `frontend/Dockerfile[.web/.web.cn]`：
    解压后对 `*.wasm/*.js/*.mjs` 执行 `gzip -k -9` 静态预压缩。
  - `frontend/selenium_tests/run_tests.sh` 构建命令同步 `--wasm`（避免本地构建
    与 CI renderer 漂移）。
  - 修复 dart2wasm 构建白屏（流水线 500 实测 selenium_tests_prod 40 分钟
    超时）：Debian nginx 的 mime.types 无 `.mjs` 条目，`main.dart.mjs` 返回
    `application/octet-stream`，浏览器对 module script 严格 MIME 校验拒绝
    加载（`Failed to load module script... MIME type of application/octet-stream`），
    Flutter 应用永不渲染。`nginx.conf` 新增 `location ~ \.mjs$` 显式声明
    `application/javascript` MIME（location 级 types 表替换默认表，仅影响 .mjs）。
  新增回归测试 `frontend/test/web_first_paint_optimization_test.dart`（9 用例，
  断言 nginx 压缩与 mjs MIME 配置、preload 决策、部署镜像预压缩、CI --wasm
  与工具链）。
- CI 所有 job 增加失败自动重试（issue #12）：全局 `default.retry`（max 2 /
  `when: [always]`，本实例 GitLab CE < 15.11 限制 retry:max 最大 2 且不支持
  retry:interval）；`build_images` / `deploy_to_synology` / `deploy_to_code01`
  三个关键 job 在脚本内自建重试循环补充（子 shell 包裹整个 script 主体，
  最多 10 次、间隔 5 秒，`exit`/`set -e` 语义不变，部署幂等）。解决 CI 因
  NAS daemon 间歇性卡死（unknown_failure）导致的失败需要人工重试的问题。
