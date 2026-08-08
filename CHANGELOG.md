# Changelog

所有重要变更均记录在此文件。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Fixed

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
