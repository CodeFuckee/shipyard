# Changelog

All notable changes to Mobile Portainer Flutter will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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
