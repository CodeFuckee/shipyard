// 字体代理 Service Worker
//
// Flutter Web 的 CanvasKit 引擎渲染中文文本时，会从 fonts.gstatic.com
// 下载 Noto Sans SC 分块字体文件（国内无法访问）。本 SW 将 gstatic 字体
// 请求改写为同源 /fonts/{path}，由后端提供磁盘持久化缓存代理，
// 后端未命中时才回源 gstatic 下载。
//
// 说明：Flutter 3.41 的官方 flutter_service_worker.js 已弃用（激活即自注销），
// 无需 importScripts 合并；本 SW 仅拦截字体请求，其他请求放行给浏览器默认处理。
'use strict';

const FONTS_HOST = 'https://fonts.gstatic.com/';

self.addEventListener('install', () => {
  // 立即激活，避免 flutter.js 等待 SW 激活超时（默认 4s）
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  // 立即接管页面，保证首次加载时引擎发出的字体请求即被拦截
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET' || !request.url.startsWith(FONTS_HOST)) {
    return; // 非 gstatic 字体请求放行
  }
  const path = request.url.slice(FONTS_HOST.length);
  const rewritten = new URL(`/fonts/${path}`, self.location.origin).toString();
  event.respondWith(
    fetch(rewritten, { mode: 'same-origin', credentials: 'omit' })
  );
});
