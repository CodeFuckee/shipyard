# 首帧加载速度测量

本文档说明 Flutter 首帧加载速度的测量方法与优化记录（issue #4）。

## Web 端测量（自动化，CI 集成）

`selenium_tests/tests/test_first_frame.py` 通过 Chrome DevTools Protocol 在页面
加载前注入计时脚本，以浏览器 `performance.now()` 为基准记录以下时间点：

- `flt-glass-pane` 出现（Flutter 渲染层挂载，即首帧渲染完成）
- `flutter-view` 出现（应用挂载）

测量策略：

1. 连续导航 10 次，丢弃前 3 次（浏览器资源冷加载 + chromedriver/Chrome
   进程预热），统计后 7 次的中位数。
2. 仅支持 Chrome（依赖 CDP），Firefox 下自动跳过。
3. 不写硬性阈值断言（首帧耗时受 CI 机器性能影响大），结果通过
   `-s` 输出，供人工与 CI 报告对比。

本地运行：

```bash
cd selenium_tests
./run_tests.sh --build-web -s tests/test_first_frame.py
```

## 移动端测量（真机/模拟器）

使用 Flutter 内置的启动时间追踪，无需侵入代码：

```bash
flutter run --profile --trace-startup
```

输出中关注 `timeToFirstFrame`（首次渲染耗时，不含 Dart 初始化）。
对比优化前后同设备同场景的数值即可判断效果。

## 优化记录（issue #4）

### 改动内容（`lib/main.dart`）

1. **通知服务初始化延迟到首帧后**：`NotificationService.initialize()` 原在
   `runApp()` 之前串行 await。Android 13+ 上
   `requestNotificationsPermission()` 会弹出系统权限对话框，用户未响应前
   首帧一直被阻塞（白屏）。该服务当前无业务调用方，延迟到首帧后
   `addPostFrameCallback` 中执行，失败静默。
2. **移动端冷启动深链检查与语言设置读取并行化**：`ConnectService.initialLink()`
   （app_links 平台通道，10-100ms）与 SharedPreferences 读取互不依赖，
   由串行 await 改为并行启动，总耗时从两者之和降为最大值。
   深链处理仍保持 AuthGate 判定之前完成的时序语义。

### 测量结果

| 场景 | 首帧中位数（热缓存） | 说明 |
|------|---------------------|------|
| 优化前（Web） | 340ms | 7 次有效样本 |
| 优化后（Web） | 338ms | 7 次有效样本，无劣化 |

Web 端 main() 中通知初始化为空实现、initialLink 直接返回 null，因此
收益集中在移动端：Android 权限对话框阻塞消除 + 串行通道调用并行化。
Web 计时测试作为回归保障（防首帧劣化）。
