# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## 语言

所有回复、注释和文档使用中文。

## 运行命令

```bash
# 本地开发
python3 main.py
# 或: uvicorn main:app --host 0.0.0.0 --port 8000 --reload

# Docker 部署
docker-compose up -d --build
```

## 项目要点

- 没有 `__init__.py` 文件，依赖 Python 3.3+ 的隐式命名空间包（PEP 420），不要添加
- Docker 镜像中 `--reload` 是有意保留的，方便开发时热重载
- 数据库通过 `Base.metadata.create_all()` 在启动时创建，无迁移脚本
- 数据库表已有数据时，不能直接删除表或清空数据，必须通过迁移保留
- 没有测试框架和代码检查工具，格式化使用 ruff

## 安全模型

- API 端点通过 `X-API-Key` 请求头认证（对照 SQLite 数据库校验）
- 管理端点需要 `X-Admin-User` + `X-Admin-Pass` 请求头（对照环境变量校验）
- WebSocket 端点通过查询参数 `api_key` 认证

## 环境变量

参考 `app/core/config.py`。关键变量：
- `ADMIN_USER` / `ADMIN_PASSWORD` — Web UI 登录凭据（默认 admin/password）
- `HOST_FILESYSTEM_ROOT` — 主机文件系统挂载路径（默认 `/hostfs`）

## 提交规范

提交信息格式：`类型(范围): 中文描述`
类型包括：feat、fix、chore、docs、refactor
