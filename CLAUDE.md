# CLAUDE.md

Shipyard — 移动端容器管理平台。Monorepo 结构，详见 `AGENTS.md`。

- 后端: `backend/` (Python FastAPI)
- 前端: `frontend/` (Flutter)

## 前端对话框规则

- 仅手机端（`PlatformDetector.isAndroid` / `isIOS` / `isOhos` 之一为 true）才使用 `showModalBottomSheet` 弹出底部操作菜单。
- 其他端（Web、桌面等非手机端）一律使用 `showDialog` + `AlertDialog` 弹出居中对话框，禁止使用 `showModalBottomSheet`。
- 平台判断统一使用 `frontend/lib/utils/platform_detector_io.dart` / `platform_detector_web.dart` 中的 `PlatformDetector`，不要直接用 `kIsWeb` 或 `Platform.xxx`。
