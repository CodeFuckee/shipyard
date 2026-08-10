---
name: docker-mirror-pull
description: >
  用户给定一个 Docker 镜像（如 langgenius/dify-plugin-daemon:0.6.3-local），
  自动搜索国内可用的 Docker 镜像源，然后尝试用不同镜像前缀拉取，失败自动切换，
  直到拉取成功。适用于国内无法直接访问 Docker Hub 的场景。
---

# Docker 镜像国内加速拉取

核心流程：**解析镜像名 → 搜索国内可用镜像源 → 拼接镜像地址 → 逐个调用 pull.py 尝试 → 成功即停止**。

## 设计原则

- **脚本预生成**：`pull.py` 已提前写好，位于本 skill 目录下。AI 不需要每次生成脚本，只需要搜索镜像源并拼接镜像名，然后调用脚本即可。
- **搜索用 AI，执行用脚本**：搜索当前可用的国内镜像源使用 AI 的 WebSearch 能力（镜像源地址经常变化），实际的 `docker pull` 操作由 `pull.py` 执行，避免大量 token 消耗在拉取日志上。
- **AI 控制切换**：AI 逐个拼接镜像名并调用脚本，根据退出码决定是否尝试下一个镜像源。

## 工具脚本

`pull.py` 位于 `~/.claude/skills/docker-mirror-pull/pull.py`，**使用 `sudo docker` 拉取，镜像存入系统级 Docker daemon，所有用户共享**。

```
python3 ~/.claude/skills/docker-mirror-pull/pull.py <完整镜像名> [原始镜像名]
```

- `完整镜像名`（必填）：已拼接镜像源前缀的完整地址，如 `docker.1ms.run/langgenius/dify-plugin-daemon:0.6.3-local`
- `原始镜像名`（可选）：拉取成功后额外打上的原始标签，如 `langgenius/dify-plugin-daemon:0.6.3-local`

退出码：`0` = 成功，非 `0` = 失败。脚本内置 sudo 权限预检，如需密码会在终端提示输入。

---

## 工作流程

### 第一步：解析用户输入

从用户消息中提取 Docker 镜像名。如果用户没有提供，主动询问。

### 第二步：搜索国内可用镜像源

使用 WebSearch 搜索当前可用的国内 Docker 镜像加速器。搜索关键词：
- `国内 Docker 镜像加速器 2026 可用`
- `Docker Hub 国内镜像源 最新`
- `docker pull 国内加速 镜像代理`

从搜索结果中提取镜像源前缀（域名部分），整理成列表。**至少收集 5-10 个**。

已知常用镜像源（作为兜底）：
- `docker.1ms.run`
- `docker.m.daocloud.io`
- `dockerproxy.com`
- `dockerhub.icu`
- `hub.rat.dev`
- `docker.hpcloud.cloud`
- `docker.registry.cyou`

### 第三步：逐个拼接并尝试拉取

对每个镜像源，执行以下步骤：

1. **拼接完整镜像名**：`{镜像源前缀}/{原始镜像名}`
   - 例如：`docker.1ms.run/langgenius/dify-plugin-daemon:0.6.3-local`
   - ⚠️ 注意：如果镜像名已经以 `library/` 开头（如官方镜像），直接拼接即可

2. **调用脚本**：
   ```bash
   python3 ~/.claude/skills/docker-mirror-pull/pull.py "docker.1ms.run/langgenius/dify-plugin-daemon:0.6.3-local" "langgenius/dify-plugin-daemon:0.6.3-local"
   ```
   - 第一个参数：拼接后的完整镜像名
   - 第二个参数：原始镜像名（用于成功后自动打 tag）

3. **判断结果**：
   - 退出码 `0` → 拉取成功，**流程结束**，报告结果
   - 退出码非 `0` → 拉取失败，**尝试下一个镜像源**
   - 所有镜像源都失败 → 报告全部失败

### 第四步：报告结果

- **成功时**：告知用户使用的镜像源和最终镜像名
- **全部失败时**：告知用户检查网络或 Docker 服务状态，给出手动排查建议

---

## 重要规则

1. **不要提前生成脚本**：`pull.py` 已预先生成好，直接使用即可
2. **每次只调用一个镜像源**：调用一次 `pull.py` → 检查退出码 → 决定是否继续
3. **已内置 sudo**：脚本默认使用 `sudo docker`，无需额外处理权限
4. **不要等待用户确认**：搜索到镜像源后直接开始拉取，无需用户确认每个镜像源

---

## 示例交互

用户输入：
```
帮我拉取 langgenius/dify-plugin-daemon:0.6.3-local
```

技能执行：
1. 解析 → 原始镜像: `langgenius/dify-plugin-daemon:0.6.3-local`
2. WebSearch → 获取 8 个可用镜像源
3. 拼接并尝试：
   ```
   python3 pull.py "docker.1ms.run/langgenius/dify-plugin-daemon:0.6.3-local" "langgenius/dify-plugin-daemon:0.6.3-local"
   → 失败 (超时)
   python3 pull.py "docker.m.daocloud.io/langgenius/dify-plugin-daemon:0.6.3-local" "langgenius/dify-plugin-daemon:0.6.3-local"
   → 成功 ✓
   ```
4. 报告：通过 `docker.m.daocloud.io` 拉取成功，本地镜像 `langgenius/dify-plugin-daemon:0.6.3-local`
