---
name: deploy
description: 构建并部署 Docker 镜像。触发 docker-compose up -d --build，部署前检查 Docker 环境。
disable-model-invocation: true
---

# 部署

执行 Docker Compose 构建和部署。

## 步骤

1. 确认 Docker 守护进程正在运行：
   ```bash
   docker info > /dev/null 2>&1 && echo "Docker 运行中" || echo "Docker 未运行"
   ```

2. 确认 docker-compose.yml 存在且 Docker socket 挂载正确。

3. 执行部署：
   ```bash
   docker-compose up -d --build
   ```

4. 检查容器状态：
   ```bash
   docker-compose ps
   ```

5. 验证服务可访问：
   ```bash
   curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/
   ```

如果部署失败，检查：
- Docker socket 是否挂载（`/var/run/docker.sock`）
- 端口 8000 是否被占用
- `.env` 文件中的环境变量是否正确
