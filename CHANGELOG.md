# Changelog

所有重要变更均记录在此文件。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Added

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
