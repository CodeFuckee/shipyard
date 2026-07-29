# Changelog

All notable changes to Mobile Portainer Flutter will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- MIT License file

### Fixed
- Narrow screen navigation bar rendering detection
- `unused_import` warning for `error_view.dart` in container details screen

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
