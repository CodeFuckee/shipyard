---
name: i18n
description: 添加国际化字符串到 ARB 文件。同时更新 app_en.arb 和 app_zh.arb。
---

当用户需要添加新的国际化字符串时：

1. 在 `lib/l10n/app_en.arb` 中添加新条目，使用 camelCase 作为 key，英文作为 value。
2. 在 `lib/l10n/app_zh.arb` 中添加相同的 key，中文作为 value。
3. 保持 JSON 格式正确，注意逗号和缩进与已有条目一致。
4. 完成后提醒用户运行 `flutter gen-l10n` 重新生成本地化代码。

使用方式：`AppLocalizations.of(context)!.keyName`

注意：如果 value 中包含变量占位符，使用 `{variableName}` 格式（如 `"msgCurrentApi": "Current API: {api}"`）。
