# 阶段1: 编译 Flutter Web
FROM cirruslabs/flutter:stable AS builder

WORKDIR /app

# 先复制依赖文件，利用 Docker 缓存层
COPY pubspec.yaml ./
RUN flutter pub get

# 复制源码和 web 配置
COPY lib/ ./lib/
COPY web/ ./web/
# 构建 Web 版本
RUN flutter build web --base-href / --release

# 阶段2: Nginx 提供静态文件服务
FROM nginx:alpine

# 复制构建产物
COPY --from=builder /app/build/web /usr/share/nginx/html

# 复制 nginx 配置
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
