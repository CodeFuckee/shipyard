# AGENTS.md

Shipyard 是一个前后端 monorepo。AI Agent 在此目录工作时需注意：

## 项目结构

- `backend/` — Python FastAPI 后端，详见 `backend/AGENTS.md`
- `frontend/` — Flutter 移动端，详见 `frontend/AGENTS.md`

## 语言

所有回复、注释和文档使用中文。

## 工作目录

涉及后端代码时在 `backend/` 目录下操作，涉及前端代码时在 `frontend/` 目录下操作。

## 合并说明

本仓库通过 `git subtree` 合并了原 `mobile_portainer`（后端）和 `mobile_portainer_flutter_module`（前端）两个独立仓库，完整保留了各自的 git 历史。
