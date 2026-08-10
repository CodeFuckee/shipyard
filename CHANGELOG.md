# Changelog

所有重要变更均记录在此文件。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Added

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
