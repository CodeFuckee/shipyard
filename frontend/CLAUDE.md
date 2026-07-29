# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

这是一个 Flutter **module**（add-to-app 模式），非独立 App。用途是 Docker/Portainer 移动端管理客户端，嵌入到原生宿主 App 中使用。

目标平台：Android、iOS、macOS、OpenHarmony (ohos)。

## 构建与检查

```bash
flutter pub get          # 安装依赖
flutter analyze          # 静态分析（flutter_lints v5，标准规则）
flutter test             # 运行测试
```

`dart format` 禁止运行（全局规范）。

## 状态管理

项目不使用 BLoC、Riverpod、Provider 等状态管理库，**全部使用 `setState`**。新增功能时延续此模式，勿引入第三方状态管理。

## 国际化

使用 ARB 格式，支持英文和中文。locale 字符串文件：
- `lib/l10n/app_en.arb`
- `lib/l10n/app_zh.arb`

修改 ARB 文件后运行 `flutter gen-l10n` 重新生成。

## 鸿蒙平台

鸿蒙相关的 shared preferences 有独立实现（`HarmonyosPreferences`），因为 `shared_preferences` 插件在鸿蒙上不可用。涉及本地存储时需通过 `PlatformDetector.isOhos` 判断平台。

**引入任何第三方库前，必须确认该库是否支持鸿蒙（OpenHarmony）平台。** 不支持鸿蒙的库需通过平台抽象（如 `io`/`web`/`ohos` 分层实现）隔离，不可直接在核心逻辑中引用。已在项目中采用的平台抽象模式（`http_helper`、`ws_helper`、`file_helper`、`platform_detector`、`notification_service`）作为参考模板。

## API 连接

用户在 App 设置界面手动输入 Portainer 服务器地址和 API Key，无硬编码端点。`DockerService` 支持 TLS 忽略选项。

## Git 规范

直接提交到 `main` 分支，无需 feature 分支或 PR 流程。

## 编译规则

**每次代码修改后，必须运行 `flutter analyze` 确保零 error**。warning 和 info 级别可以保留，但 error 必须为零。修改代码前先跑一次分析确认基线，修改后再跑一次确认没有新引入 error。
**每次代码修改完成后，必须运行 `flutter build web` 验证 Web 端编译成功。**

## 注意事项

- `test/widget_test.dart` 是 `flutter create` 生成的默认计数器测试，与当前 App 不匹配（`MyApp` 渲染的是 `MainTabScreen`），运行会失败。修复或替换前勿依赖它。
- `macos/` 目录已暂存但尚未提交，包含 macOS Runner 项目。
