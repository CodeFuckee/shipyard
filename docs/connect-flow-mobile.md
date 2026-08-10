# 移动端网页授权添加服务器(/connect)技术方案

> 状态:已实现(2026-08-10) · 关联:GitLab issue
> [#3](https://home.chenkaidi.top:509/chenkaidi/shipyard/-/work_items/3)
> Web 端已实现,见 `backend/app/routers/connect.py` 与
> `frontend/lib/services/connect_service.dart`。

## 背景

Web 端已支持"网页授权添加服务器":在 app 中输入目标 Shipyard 服务器 URL,
跳转到该服务器的交互式授权页,登录/确认后携带一次性授权码回跳,换得独立
apikey 自动添加。流程类似 OAuth2 授权码 + PKCE。

移动端(Android / iOS / HarmonyOS)未实现的原因:**移动端没有"跳出去再
跳回来"的基建**——url_launcher 只能单向打开系统浏览器,没有深链接收能力。

## 协议(与 Web 端完全共享,后端零改动)

目标服务器(被添加方)提供以下端点,移动端与 Web 端调用方式完全一致:

| 端点 | 作用 |
|---|---|
| `GET /connect/capabilities` | 能力探测,返回 `{"enabled": true}`;老版本部署被 nginx SPA 回退成 index.html,解析 JSON 失败即判定不支持,回退手动输入 |
| `POST /connect/register` | 注册 public client(无 secret),保存 redirect_uri 白名单 |
| `GET /connect/authorize` | 交互式授权页(后端 HTML 模板):已登录显示确认按钮、未登录显示登录表单 |
| `GET /connect/session` | cookie 会话检查 |
| `POST /connect/login` | 管理员凭据换 HttpOnly 会话 cookie |
| `POST /connect/confirm` | 会话鉴权后生成一次性授权码(10 分钟),302 回跳携带 `code` + `state` |
| `POST /connect/token` | PKCE verifier 换取独立 apikey(note 记录来源,可单独撤销) |

安全约束与 Web 端一致:state 防 CSRF、PKCE 防授权码拦截、redirect_uri 必须
与注册值一致、授权码一次性、回调只带 code(apikey 走 POST 响应体)。

## 移动端需要的深链基建(本次改动核心)

### 1. 依赖

- 新增 `app_links`(或 `uni_links`),监听应用回跳。
- `url_launcher` 已有,负责跳往目标服务器授权页。

### 2. 回调 scheme(三端)

授权页 302 回跳到 `redirect_uri`,移动端必须能让系统浏览器把该 URI
转交给 app:

- **Android**:`AndroidManifest.xml` 声明 intent-filter,支持
  `shipyard://connect/callback`(自定义 scheme)或 https 深链
  (App Links 需域名验证,自部署场景不可行,推荐自定义 scheme)。
- **iOS**:`Info.plist` 声明 `CFBundleURLTypes`,注册 `shipyard` scheme。
- **HarmonyOS**:`huawei/` 工程中声明 scheme 能力
  (参考 `frontend/huawei/hvigorconfig.ts` 与 module.json5 的 skills 配置)。

回跳 URL 形如 `shipyard://connect/callback?code=xxx&state=yyy`。

### 3. 冷启动恢复

用户可能长时间停留在授权页,app 被杀后回跳:

- `app_links` 的 `getInitialLink()` 处理冷启动(app 被杀后由系统拉起);
- `linkStream` 处理热启动(后台恢复)。

两种情况都要能完成 token 交换,处理完成前需要显示加载页。

### 4. 平台化的 ConnectService

现有 `frontend/lib/services/connect_service.dart` 依赖 `dart:js_interop`
(sessionStorage / window / history),仅 Web 可编译。移动端需要:

- `buildRedirectUri()` 平台化:Web 返回 `{origin}/connect/callback`,
  移动端返回 `shipyard://connect/callback`。
- state / code_verifier 存储:Web 用 sessionStorage(整页刷新可恢复);
  移动端存 SharedPreferences(冷启动后可恢复),键名与 Web 端不冲突。
- URL 参数清理:Web 用 `history.replaceState`;移动端无此问题
  (scheme 回调不改变 app 内 URL)。
- 跳转:Web 用 `window.location`;移动端用 `url_launcher`
  `launchUrl(..., mode: LaunchMode.externalApplication)`。
- 回调处理位置:Web 在 `main.dart` 的 main() 中、AuthGate 之前;
  移动端在 app_links 事件回调中处理,处理逻辑抽成共用函数
  (建议放入 `ConnectService.handleCallback(Uri)`)。

### 5. 移动端特有的行为差异

- **"已登录"判定**:授权页的登录态是目标服务器系统浏览器中的 cookie
  会话,与 app 内的登录完全无关——这是预期行为,无需处理。
- **探测失败回退**:与 Web 一致,回退到手动输入对话框。
- **深链被拒**:用户可能没有可处理 `shipyard://` 的 app(例如从桌面
  浏览器打开授权页)——授权页 302 到未知 scheme 会提示无应用。
  备选:授权页展示 apikey 由用户手动复制(需要后端新增"直接展示 key"
  模式,不建议默认开启)。

## 实现清单(按序)

1. [x] pubspec 增加 `app_links`(Android/iOS/桌面深链)与 `crypto`
      (io 端 SHA-256);鸿蒙不引入插件,深链走
      `huawei/entry/src/main/module.json5` skills `uris`
      (`shipyard://connect/callback`) + `EntryAbility` 捕获,
      `HarmonyPlatformPlugin` 新增 `getInitialDeepLink`/`consumeDeepLink`
      通道方法。
2. [x] `ConnectService` 拆平台分支(io/web):
      - `connect_platform_io.dart` 从抛错 stub 改为完整实现:redirect
        (ohos 走 `HarmonyosPlatform.launchUrl`,其余走 url_launcher)、
        纯 Dart SHA-256、`PreferencesService` 存储(鸿蒙 preferences /
        SharedPreferences)。
      - `buildRedirectUri()`:Web 返回 origin 路径,移动端返回
        `shipyard://connect/callback`。
      - 回调处理抽为共用:Web 走 `Uri.base` + `clearCallbackParams`,
        移动端走 `initialLink()`(冷启动)/`pendingLink()`(热启动)
        + `completeFlow(Uri)`。
      - `probe()` 去掉 `if (!kIsWeb) return false;`,移动端可真实探测。
3. [x] 设置页"网页授权添加"入口对移动端开放
      (Android/iOS/鸿蒙;桌面端保持隐藏),探测成功卡片对移动端
      增加"将打开系统浏览器"提示。
4. [x] 冷启动 + 热启动回跳处理:
      - 冷启动:`main()` 在 runApp 前消费 `initialLink()`,完成 token
        交换与服务器添加(与 Web 端 AuthGate 前处理对齐)。
      - 热启动:`_MyAppState` 生命周期监听,app 恢复(resumed)时消费
        `pendingLink()`,交换期间显示加载对话框(防重入)。
      - `_addServerFromConnect` 改用 `PreferencesService`,修复鸿蒙
        上 `SharedPreferences` 不可用的问题。
5. [x] 回归:两端共用同一套 /connect 协议,后端与 nginx 零改动。

## Android/iOS 宿主工程声明(本仓库外,需宿主侧配合)

本仓库为 Flutter module(add-to-app),`android/`/`ios/` 宿主工程不在此
仓库内。app_links 插件代码已接入,宿主工程需声明 `shipyard://` scheme:

- **Android**(宿主 `AndroidManifest.xml` 的 MainActivity):
  ```xml
  <intent-filter android:autoVerify="false">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="shipyard" android:host="connect" android:pathPrefix="/callback" />
  </intent-filter>
  ```
- **iOS**(宿主 `Info.plist`):
  ```xml
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLSchemes</key>
      <array><string>shipyard</string></array>
    </dict>
  </array>
  ```

鸿蒙 scheme 已在 `huawei/` 工程内声明完毕,无需宿主操作。
