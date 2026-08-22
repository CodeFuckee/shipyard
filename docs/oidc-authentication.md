# OIDC 统一身份认证

Shipyard 支持使用符合 OpenID Connect Discovery 的身份提供商登录，例如
Keycloak、Authentik、Authelia。启用后，登录页会显示“通过统一身份认证登录”按钮；
未启用或 IdP 暂不可用时，原有 `ADMIN_USER` / `ADMIN_PASSWORD` 本地管理员登录始终保留，
可用作紧急回退。

## 安全模型

- 使用 **授权码流程 + PKCE（S256）**；浏览器和移动端均生成并校验一次性 `state`。
- 每次登录均携带 OIDC `nonce`，后端校验 ID Token 的签名（JWKS）、`issuer`、`audience`、
  有效期和 `nonce`；不会把 IdP 的 ID Token 保存到客户端或数据库。
- 回调地址必须精确列入 `OIDC_REDIRECT_URIS` 白名单，防止授权码被转发到未授权地址。
- OIDC 的 `issuer + sub` 稳定映射为 Shipyard API Key；显示名变化不会产生新账号。
- 当前 Shipyard 的权限模型为单管理员模型，因此通过 OIDC 成功登录的用户默认拥有管理员权限。
  接入前应仅允许受信任的 IdP 用户访问应用；后续角色/组映射可在多角色模型引入时扩展。

## 部署配置

以下变量必须一起配置；任意必要变量缺失时，OIDC 按未启用处理：

| 变量 | 说明 |
| --- | --- |
| `OIDC_ISSUER` | IdP 的 HTTPS issuer，例如 `https://sso.example.com/realms/home`；必须支持 `/.well-known/openid-configuration`。 |
| `OIDC_CLIENT_ID` | 在 IdP 创建的 Shipyard OIDC 客户端 ID。 |
| `OIDC_CLIENT_SECRET` | 机密客户端的 secret；公有 PKCE 客户端可留空。请仅通过部署环境注入。 |
| `OIDC_REDIRECT_URIS` | 逗号分隔的精确回调白名单。Web 回调为 `https://<shipyard-host>/oidc/callback`；移动端回调为 `shipyard://oidc/callback`。 |
| `OIDC_DISCOVERY_TIMEOUT` | 可选，发现、JWKS 和 token 请求超时秒数，默认 `10`。 |

以 Keycloak 为例：

```bash
OIDC_ISSUER=https://sso.example.com/realms/home
OIDC_CLIENT_ID=shipyard
OIDC_CLIENT_SECRET=请通过密钥管理系统注入
OIDC_REDIRECT_URIS=https://shipyard.example.com/oidc/callback,shipyard://oidc/callback
```

在 IdP 中将上述两个回调地址添加到客户端的 **Valid Redirect URIs**，并启用授权码流程。
不要使用通配符回调地址，也不要把 `OIDC_CLIENT_SECRET` 写入仓库或前端构建产物。

## 客户端回调

Android、iOS、macOS 和鸿蒙客户端已注册 `shipyard://` 自定义 scheme。原生客户端首次使用时，
在登录页选择“配置统一身份认证服务器”，填入 Shipyard 的 HTTPS 地址后即可检测并开始登录；
用户在系统浏览器完成认证后，应用会校验回调状态并向 Shipyard 后端交换 API Key。Web 使用当前
站点 origin 下的 `/oidc/callback`，nginx 的 SPA 回退会加载应用并完成同一流程。

Shipyard 的 Flutter 项目以 add-to-app module 形式嵌入 iOS 宿主；iOS 宿主工程应注册同一
`shipyard` URL scheme，才能接收 `shipyard://oidc/callback` 回跳。
