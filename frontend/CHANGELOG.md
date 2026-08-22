# Changelog

All notable changes to Mobile Portainer Flutter will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- 容器详情页的每个已映射端口新增“打开网页”按钮（issue #45）：以当前 Docker 服务
  地址的主机名和宿主机端口生成 HTTP 地址，并在外部浏览器打开；支持 IPv6，未映射或
  非法端口不显示按钮。

- 底部 AI 聊天入口升级为双行扩展式输入面板：采用白色圆角卡片、柔和阴影与
  横向可滚动的 Docker 能力展示项（快速、Docker 指令、容器状态、查看日志、
  清理镜像、更多）；能力项当前仅作视觉展示，保留既有关闭与发送对话逻辑。
- AI agent 未配置 Hermes 时回退自研 langchain（issue #21，第四轮）：
  ① 503 弹窗（llm_not_configured）改为双入口——「配置 Hermes」与
  「配置 AI 供应商」，分别跳转对应配置页（手机端底部菜单、其他端居中
  对话框，遵循项目对话框规则）；
  ② AI 供应商配置页支持默认供应商标记：「设为默认 / 取消默认」操作
  （操作菜单内，默认供应商显示「默认」徽标），`AuthService.updateAiProvider`
  新增 isDefault 参数提交 is_default 字段。
- AI 聊天入口改为底部导航栏原位展开的 Codex 风格输入框：支持返回导航、
  空输入禁用发送；发送首条消息后自动打开完整聊天界面并启动流式回复。
- 首帧加载速度测量测试（`selenium_tests/tests/test_first_frame.py`）：通过
  CDP 注入 + 浏览器 Performance API 计时，测量 `flt-glass-pane` / `flutter-view`
  出现耗时（10 次导航丢弃 3 次预热取中位数），用于验证首帧优化效果并防回归；
  测量方法详见 `docs/first_frame_measurement.md`
- MIT License file
- Project list: explicit delete entry — each project card now shows a delete
  icon (top-right) that opens a confirmation dialog, calls `DELETE /projects/{id}`
  (stops containers via compose down, removes the DB record and the server-side
  project folder), and refreshes the list on success. The previous long-press
  delete interaction was removed in favor of this explicit action. Added
  `tooltipDeleteProject` i18n string (en/zh) and 5 widget tests
  (`test/projects_delete_test.dart`).

### Fixed
- 修复右边栏弹出/关闭时页面完全黑屏（issue #29）：`showGeneralDialog`
  遮罩色 `Colors.black.withValues(alpha: 60)` 误用了 0-1 的 double
  语义（`withValues` 与 0-255 的 `withAlpha` 不同），alpha 被饱和为
  完全不透明，半透明遮罩变成纯黑——右边栏弹出与关闭动画期间
  页面被纯黑遮罩完全盖住（黑屏）。修复为 `alpha: 0.6`
  （60% 不透明，接近 Material 默认 black54）。新增 1 个 widget 测试
  （ModalBarrier 遮罩颜色断言）。
- AI 聊天发送消息 422 真因修复（issue #23，第二轮）：`AgentService.chatStream`
  的 JSON 字符串 body 未带 `Content-Type: application/json`，后端 FastAPI
  无法解析，把整个字符串绑定给 Pydantic 模型报 `model_attributes_type` 422。
  修复：请求头显式带 application/json；新增 `AgentChatHttpException` 把
  HTTP 错误转为可读提示（422 显示"请求格式错误（HTTP 422）"），聊天框
  不再展示后端原始 JSON。新增测试 6 个（Content-Type 断言、真实
  HttpServer 端到端链路、错误友好化服务层 + 页面层）。
- AI 聊天发送消息 422 修复（issue #23）：工具全不选或工具列表加载失败时
  `AgentService.chatStream` 发送 `tools: []` 空数组被后端拒绝（422），
  聊天框报网络错误。修复：tools 为空时省略 tools 字段，后端回退默认
  skill 工具；新增 `agent_service_test.dart` 复现测试 1 个。
- Narrow screen navigation bar rendering detection
- `unused_import` warning for `error_view.dart` in container details screen
- Web 端登录态校验：AuthGate 启动时通过轻量请求验证 API Key 有效性，
  残留的过期/失效/其他实例 token（401/403）会被自动清除并回到登录页，
  不再进入概览页后所有请求 401、页面直接显示 "Invalid API Key or Admin
  Credentials" 报错（`AuthService.isLoggedIn` 增加 token 验证）
- 概览页认证错误兜底：`_fetchServerData` 捕获 401/403 时不再显示后端
  原始错误并每 3 秒重试、持续报错（`DashboardScreen` 增加认证错误
  检测）；仅登录服务器（web_backend_url）凭据失效时清除凭据回到
  登录页，服务器列表其他条目的 key 失效做静默处理，避免打断用户
  操作（如网页授权添加服务器流程）
- 设置页"添加服务器"按钮增加语义 label（`Semantics`）：纯图标按钮
  在语义树中无文本可定位，Selenium 生产测试在服务器列表非空时
  依赖 aria-label 点击（`_buildAddButton`）
- 首帧加载优化（issue #4）：通知服务初始化（`NotificationService.initialize`）
  从 main() 首帧前延迟到首帧后执行——Android 13+ 的通知权限对话框若在
  首帧前等待用户响应会显著拉长白屏时间；移动端冷启动深链检查
  （`ConnectService.initialLink`，app_links 平台通道）与语言设置读取
  并行化，消除首帧前的串行等待。Web 端计时测试复测无劣化
  （优化前 340ms / 优化后 338ms，误差范围内；收益场景为移动端）

## [1.0.0] - 2025-06-09

### Added
- **Server Management**: Multi-server support with Portainer-compatible APIs, dashboard overview, and GPU monitoring.
- **Container Management**: Full lifecycle control — create, start, stop, restart, pause, kill, remove. Real-time stats, logs, file browsing.
- **Image Management**: List, pull, and remove Docker images.
- **Stacks Management**: View Docker Compose stacks and filter containers by stack.
- **Volume & Network Management**: List, inspect, and manage volumes and networks.
- **API Key Management**: Create, list, revoke API keys; QR code scanning for quick server configuration.
- **Dark Mode**: Light/dark theme following system preference.
- **Internationalization**: English and Chinese (zh-CN) support.
- **Real-time Updates**: WebSocket integration for live event streaming.
- **Notifications**: Local push notifications for container events.
- **Responsive Design**: Adaptive layouts for mobile, tablet, and desktop.
- **5-Platform Support**: Android, iOS, macOS, Web, OpenHarmony (Hongmeng).
- **Docker Deployment**: Web version deployable via `Dockerfile.web`.
- Bilingual README with screenshots (English & Chinese).
- GitHub Actions CI/CD pipeline (analyze + build web).
- Issue templates (bug report, feature request) and PR template.
- Contributing guide.
