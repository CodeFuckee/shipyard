---
name: check
description: 对项目代码运行快速质量检查——语法验证、导入检查、基础问题扫描。
---

# 代码检查

使用 ruff 对项目 Python 代码进行快速静态检查。

## 步骤

1. 检查所有 Python 文件的语法和导入：
   ```bash
   python3 -m ruff check app/ main.py --select E,F,I --show-files
   ```

2. 如果发现问题，报告具体文件和行号。常见问题：
   - `E` 类错误：语法/缩进问题（必须修复）
   - `F` 类错误：未定义变量、未使用导入（建议修复）
   - `I` 类错误：导入排序问题（可选修复）

3. 对于可自动修复的问题，运行：
   ```bash
   python3 -m ruff check app/ main.py --select E,F,I --fix
   ```

4. 格式化检查：
   ```bash
   python3 -m ruff format --check app/ main.py
   ```

## 注意

只报告问题，不要自动修改代码，除非用户明确要求 `--fix`。
