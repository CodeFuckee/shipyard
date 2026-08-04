"""跨实例服务器授权添加（/connect 流程）。

与 MCP OAuth（/register /authorize /token）完全隔离：本流程面向
"在 app A 上添加服务器 B" 的场景，采用交互式授权页 + 授权码 + PKCE：

    源 app(Flutter Web) ──探测/注册/跳转──▶ 目标服务器授权页
        ◀──登录/确认/302 回跳 code──
        源 app 用 code+verifier 换独立 apikey → 写入服务器列表

安全设计：
- 交互式授权页大号展示 client 名称与回调地址（防动态注册钓鱼）
- redirect_uri 必须与注册值一致（防授权码转发）
- PKCE：code_verifier 仅存源 app 的 sessionStorage，code 泄露无法换 key
- 一次性授权码，10 分钟有效，用后即删
- 签发的 apikey 为独立新 key（note 记录来源），可单独撤销，
  不与现有共享 apikey 混用
- 登录会话独立于现有无状态 X-API-Key 认证，仅服务授权流程

探测协议：GET /connect/capabilities 返回 JSON；老版本部署的 nginx
会把未知路径 SPA 回退成 index.html（200 HTML），前端解析 JSON 失败
即判定不支持，回退手动输入。
"""

import hashlib
import html
import secrets
import time
import uuid

from fastapi import APIRouter, Depends, Form, HTTPException, Query, Request, Response
from fastapi.responses import HTMLResponse, RedirectResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.core.security import verify_admin_credentials
from app.db.database import get_db
from app.db.models import (
    APIKeyModel,
    ConnectAuthCodeModel,
    ConnectClientModel,
    ConnectSessionModel,
)

router = APIRouter(prefix="/connect", tags=["connect"])

# 会话与授权码有效期
SESSION_TTL_SECONDS = 7 * 24 * 3600  # 登录会话 7 天
CODE_TTL_SECONDS = 600  # 授权码 10 分钟
COOKIE_NAME = "connect_session"


class RegisterRequest(BaseModel):
    redirect_uri: str = Field(min_length=1, max_length=2048)
    client_name: str = Field(default="", max_length=128)


class LoginRequest(BaseModel):
    username: str = Field(min_length=1, max_length=256)
    password: str = Field(min_length=1, max_length=256)


class TokenRequest(BaseModel):
    client_id: str = Field(min_length=1, max_length=128)
    code: str = Field(min_length=1, max_length=128)
    code_verifier: str = Field(min_length=43, max_length=128)


class SessionBindRequest(BaseModel):
    api_key: str = Field(min_length=1, max_length=128)


# ================================================================
# 内部辅助
# ================================================================


def _cleanup_expired(db: Session) -> None:
    """惰性清理过期的会话和授权码。"""
    now = time.time()
    db.query(ConnectSessionModel).filter(
        ConnectSessionModel.expires_at < now
    ).delete()
    db.query(ConnectAuthCodeModel).filter(
        ConnectAuthCodeModel.expires_at < now
    ).delete()
    db.commit()


def _get_session_token(request: Request) -> str | None:
    """从 cookie 读取会话 token。"""
    return request.cookies.get(COOKIE_NAME)


def _require_session(db: Session, token: str | None) -> ConnectSessionModel | None:
    """校验会话有效性（存在且未过期）。"""
    if not token:
        return None
    record = (
        db.query(ConnectSessionModel)
        .filter(ConnectSessionModel.session_token == token)
        .first()
    )
    if record is None or record.expires_at < time.time():
        return None
    return record


def create_connect_session(db: Session, response: Response) -> str:
    """创建授权流程登录会话并种下 connect_session cookie。

    主应用登录（/admin/login）与授权页登录（/connect/login）共用：
    任一处登录后，跳转授权页（/connect/authorize）都无需重复输入密码。
    返回会话 token。
    """
    token = secrets.token_hex(32)
    db.add(
        ConnectSessionModel(
            session_token=token, expires_at=time.time() + SESSION_TTL_SECONDS
        )
    )
    db.commit()

    # 写入登录会话 cookie：HttpOnly + SameSite=Lax，仅登录态判定用
    response.set_cookie(
        key=COOKIE_NAME,
        value=token,
        max_age=SESSION_TTL_SECONDS,
        httponly=True,
        samesite="lax",
        secure=False,  # 内网 http 部署常见，由 nginx 层决定 https 提升
    )
    return token


def _validate_redirect_uri(uri: str) -> str:
    """校验回调地址必须为 http/https。"""
    if not (uri.startswith("http://") or uri.startswith("https://")):
        raise HTTPException(status_code=400, detail="redirect_uri 必须是 http/https 地址")
    return uri


# ================================================================
# 探测与客户端注册（源 app 跨域调用）
# ================================================================


@router.get("/capabilities")
def capabilities():
    """能力探测：返回 JSON 表示支持 /connect 流程。

    老版本部署的 nginx 会把该路径 SPA 回退成 index.html（200 HTML），
    前端解析 JSON 失败即判定不支持。
    """
    return {"enabled": True}


@router.post("/register")
def register(data: RegisterRequest, db: Session = Depends(get_db)):
    """动态注册 public client（无 secret），保存回调地址白名单。"""
    redirect_uri = _validate_redirect_uri(data.redirect_uri.strip())
    client_id = secrets.token_hex(16)
    db.add(
        ConnectClientModel(
            client_id=client_id,
            client_name=data.client_name.strip() or "未命名客户端",
            redirect_uri=redirect_uri,
        )
    )
    db.commit()
    return {"client_id": client_id}


# ================================================================
# 授权页会话（目标服务器同源调用）
# ================================================================


@router.get("/session")
def session_status(request: Request, db: Session = Depends(get_db)):
    """会话检查：返回当前浏览器是否已登录。"""
    _cleanup_expired(db)
    record = _require_session(db, _get_session_token(request))
    return {"logged_in": record is not None}


@router.post("/session")
def session_bind(
    data: SessionBindRequest,
    response: Response,
    db: Session = Depends(get_db),
):
    """用主应用已存的 API key 自动建立授权会话（免重复输入密码）。

    浏览器登录过主应用后，API key 存于 localStorage（shared_preferences
    web 格式），但 connect_session cookie 可能缺失（如种 cookie 功能
    上线前的旧登录态）。授权页检测到 key 后调用本端点：key 与数据库
    匹配则创建会话并种 cookie，授权页即可直接显示确认按钮。
    """
    _cleanup_expired(db)
    record = db.query(APIKeyModel).filter(APIKeyModel.key == data.api_key).first()
    if record is None:
        return {"logged_in": False}
    create_connect_session(db, response)
    return {"logged_in": True}


@router.post("/login")
def login(data: LoginRequest, response: Response, db: Session = Depends(get_db)):
    """管理员凭据登录，种下 HttpOnly 会话 cookie（仅授权流程使用）。"""
    if not verify_admin_credentials(db, data.username, data.password):
        raise HTTPException(status_code=401, detail="用户名或密码错误")

    create_connect_session(db, response)
    return {"ok": True}


# ================================================================
# 授权页与确认（目标服务器页面）
# ================================================================

# 授权页内联模板：大号展示 client 名称与回调地址，防动态注册钓鱼。
# 样式对齐前端 Flutter App 的 Arco Design 主题（light/dark 双色板），
# 零外部依赖：目标服务器可能为内网离线部署，CSS/图标全部内联。
# JS 流程：查会话 → 已登录显示确认按钮 / 未登录显示登录表单 →
# 确认后 POST /connect/confirm，后端 302 回跳携带一次性 code。
_AUTHORIZE_PAGE_TEMPLATE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>授权添加服务器</title>
<meta http-equiv="Cache-Control" content="no-store">
<meta http-equiv="Pragma" content="no-cache">
<style>
  /* Arco Design 色板，与前端 Flutter App 主题一致（app_theme.dart）；
     零外部依赖（目标服务器可能为内网离线部署），light/dark 随系统 */
  :root {
    color-scheme: light dark;
    --bg: #F2F3F5;
    --card: #FFFFFF;
    --border: #E5E6EB;
    --text: #1D2129;
    --text-secondary: #4E5969;
    --primary: #165DFF;
    --primary-hover: #4080FF;
    --primary-ring: rgba(22, 93, 255, .2);
    --input-bg: #E5E6EB;
    --icon-bg: #E8F0FF;
    --warn-bg: #FFF2E5;
    --warn-border: rgba(255, 125, 0, .4);
    --warn-text: #4D1B00;
    --warn-accent: #FF7D00;
    --error: #F53F3F;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #17171A;
      --card: #232324;
      --border: #484849;
      --text: #E5E6EB;
      --text-secondary: #86909C;
      --primary: #4080FF;
      --primary-hover: #165DFF;
      --primary-ring: rgba(64, 128, 255, .25);
      --input-bg: #3A3A3D;
      --icon-bg: #002B73;
      --warn-bg: #5C2D00;
      --warn-border: rgba(255, 153, 51, .4);
      --warn-text: #FFE4CC;
      --warn-accent: #FF9933;
      --error: #F76560;
    }
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
    padding: 16px;
    background: var(--bg); color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif;
  }
  .card {
    width: min(420px, 92vw); background: var(--card);
    border: 1px solid var(--border); border-radius: 8px;
    padding: 28px 24px;
    box-shadow: 0 4px 12px rgba(0, 0, 0, .06);
  }
  .head { display: flex; align-items: center; gap: 12px; margin-bottom: 20px; }
  .head-icon {
    flex-shrink: 0; width: 40px; height: 40px; border-radius: 8px;
    display: flex; align-items: center; justify-content: center;
    background: var(--icon-bg); color: var(--primary);
  }
  h1 { font-size: 18px; font-weight: 600; margin: 0 0 4px; color: var(--text); }
  .sub { font-size: 12px; color: var(--text-secondary); }
  .warn {
    display: flex; gap: 8px; align-items: flex-start;
    background: var(--warn-bg); border: 1px solid var(--warn-border);
    color: var(--warn-text); border-radius: 8px;
    padding: 12px; font-size: 13px; line-height: 1.6; margin-bottom: 16px;
  }
  .warn svg { flex-shrink: 0; color: var(--warn-accent); margin-top: 1px; }
  .warn b { font-weight: 600; }
  .meta { border: 1px solid var(--border); border-radius: 8px; margin-bottom: 16px; overflow: hidden; }
  .meta-row { padding: 10px 12px; }
  .meta-row + .meta-row { border-top: 1px solid var(--border); }
  .meta-row span { display: block; font-size: 12px; color: var(--text-secondary); margin-bottom: 2px; }
  .meta-row b { display: block; font-size: 13px; font-weight: 600; color: var(--text); word-break: break-all; }
  .field { margin-bottom: 14px; }
  label { display: block; font-size: 13px; color: var(--text-secondary); margin-bottom: 6px; }
  input {
    width: 100%; padding: 10px 12px; border-radius: 8px;
    border: 1px solid var(--border); background: var(--input-bg); color: var(--text);
    font-size: 14px; outline: none; transition: border-color .2s, box-shadow .2s;
  }
  input:focus { border-color: var(--primary); box-shadow: 0 0 0 2px var(--primary-ring); }
  button {
    width: 100%; padding: 11px 12px; border: none; border-radius: 8px;
    background: var(--primary); color: #FFFFFF; font-size: 15px; font-weight: 600;
    cursor: pointer; margin-top: 6px; transition: background .2s;
  }
  button:hover:not(:disabled) { background: var(--primary-hover); }
  button:disabled { opacity: .6; cursor: not-allowed; }
  button.ghost {
    background: var(--card); color: var(--text);
    border: 1px solid var(--border); margin-top: 10px;
  }
  button.ghost:hover:not(:disabled) {
    border-color: var(--primary); color: var(--primary); background: var(--card);
  }
  .err { color: var(--error); font-size: 13px; margin-top: 10px; min-height: 18px; }
  .info { font-size: 12px; color: var(--text-secondary); margin-top: 14px; line-height: 1.6; }
  .info b { color: var(--text); font-weight: 600; word-break: break-all; }
</style>
</head>
<body>
<div class="card">
  <div class="head">
    <div class="head-icon">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
           stroke-linecap="round" stroke-linejoin="round" width="22" height="22" aria-hidden="true">
        <path d="M12 2l8 3v6c0 5-3.4 9-8 11-4.6-2-8-6-8-11V5l8-3z"/>
        <path d="M9 12l2 2 4-4"/>
      </svg>
    </div>
    <div>
      <h1>授权添加服务器</h1>
      <!-- 版本标记：远程诊断锚点。用户报告授权页异常时，据此判断浏览器
           是否缓存了旧版页面（无版本号 = 缓存旧页，需硬刷新） -->
      <div class="sub">此页面由目标服务器自身提供，请确认以下信息 · 版本 v4</div>
    </div>
  </div>

  <div class="warn">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
         stroke-linecap="round" stroke-linejoin="round" width="18" height="18" aria-hidden="true">
      <path d="M12 3l10 18H2L12 3z"/>
      <path d="M12 10v4"/>
      <path d="M12 17h.01"/>
    </svg>
    <div>点击确认后，本服务器将向下方<b>回调地址</b>签发一把<b>管理员级 API 密钥</b>。请确认这是你正在添加的服务器，谨防仿冒页面。</div>
  </div>

  <div class="meta">
    <div class="meta-row">
      <span>请求方</span>
      <b>__CLIENT_NAME__</b>
    </div>
    <div class="meta-row">
      <span>回调地址</span>
      <b>__REDIRECT_URI__</b>
    </div>
  </div>

  <div id="confirmBox" style="display:none">
    <button id="btnConfirm">确认并添加</button>
    <button class="ghost" id="btnCancel">取消</button>
  </div>

  <div id="loginBox" style="display:none">
    <div class="field">
      <label for="username">用户名</label>
      <input id="username" autocomplete="username">
    </div>
    <div class="field">
      <label for="password">密码</label>
      <input id="password" type="password" autocomplete="current-password">
    </div>
    <button id="btnLogin">登录</button>
    <div class="err" id="err"></div>
    <div class="info">
      未检测到本机登录凭据。若已在浏览器登录过本服务器主应用，请<b>刷新页面</b>重试；
      首次授权需输入目标服务器密码以确认身份，登录后 7 天内免重复输入。
    </div>
  </div>
</div>

<script>
  var params = new URLSearchParams(location.search);
  function hidden(name, value) {
    var el = document.createElement('input');
    el.type = 'hidden'; el.name = name; el.value = value;
    return el;
  }
  function submitConfirm() {
    var form = document.createElement('form');
    form.method = 'POST'; form.action = '/connect/confirm';
    ['client_id','redirect_uri','state','code_challenge'].forEach(function(k) {
      form.appendChild(hidden(k, params.get(k)));
    });
    document.body.appendChild(form); form.submit();
  }

  function showConfirm() {
    document.getElementById('confirmBox').style.display = 'block';
  }
  function showLogin() {
    document.getElementById('loginBox').style.display = 'block';
    try { document.getElementById('username').focus(); } catch (e) {}
  }
  // 主应用登录后凭据存 localStorage（shared_preferences web 格式：
  // flutter. 前缀；同时兼容无前缀的旧格式）。检测到 key 即自动
  // 绑定会话，免去重复输入用户名密码。
  function tryAutoBind() {
    var keys = ['flutter.docker_auth_token', 'flutter.docker_api_key',
                'docker_auth_token', 'docker_api_key'];
    var apiKey = null;
    for (var i = 0; i < keys.length; i++) {
      var v = localStorage.getItem(keys[i]);
      if (v && v.length > 8) { apiKey = v; break; }
    }
    if (!apiKey) { showLogin(); return; }
    fetch('/connect/session', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({api_key: apiKey})
    }).then(function(r) { return r.json(); })
      .then(function(s) {
        if (s.logged_in) { showConfirm(); } else { showLogin(); }
      })
      .catch(function() { showLogin(); });
  }

  fetch('/connect/session', {credentials: 'same-origin'})
    .then(function(r) { return r.json(); })
    .then(function(s) {
      if (s.logged_in) {
        showConfirm();
      } else {
        tryAutoBind();
      }
    })
    .catch(function() { showLogin(); });

  document.getElementById('btnConfirm').addEventListener('click', submitConfirm);

  document.getElementById('btnCancel').addEventListener('click', function() {
    document.getElementById('confirmBox').style.display = 'none';
    var div = document.createElement('div');
    div.className = 'warn';
    div.textContent = '已取消授权，可以关闭此页面。';
    document.querySelector('.card').appendChild(div);
  });

  var loginBtn = document.getElementById('btnLogin');
  var loginBtnText = loginBtn.textContent;
  function doLogin() {
    if (loginBtn.disabled) return;
    loginBtn.disabled = true;
    loginBtn.textContent = '登录中…';
    var err = document.getElementById('err'); err.textContent = '';
    fetch('/connect/login', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        username: document.getElementById('username').value,
        password: document.getElementById('password').value
      })
    }).then(function(r) {
      if (!r.ok) { return r.json().then(function(j) { throw new Error(j.detail || '登录失败'); }); }
      return r.json();
    }).then(function() {
      document.getElementById('loginBox').style.display = 'none';
      document.getElementById('confirmBox').style.display = 'block';
      err.textContent = '';
    }).catch(function(e) {
      err.textContent = e.message || '登录失败';
    }).finally(function() {
      loginBtn.disabled = false;
      loginBtn.textContent = loginBtnText;
    });
  }
  loginBtn.addEventListener('click', doLogin);
  // 密码框回车提交，与点击登录按钮一致
  document.getElementById('password').addEventListener('keydown', function(e) {
    if (e.key === 'Enter') doLogin();
  });
</script>
</body>
</html>
"""


@router.get("/authorize", response_class=HTMLResponse)
def authorize(
    request: Request,
    client_id: str = Query(..., min_length=1, max_length=128),
    redirect_uri: str = Query(..., max_length=2048),
    state: str = Query("", max_length=512),
    code_challenge: str = Query(..., min_length=43, max_length=128),
    db: Session = Depends(get_db),
):
    """交互式授权页。校验回调地址与注册值一致后渲染授权页面。

    响应必须禁止缓存（Cache-Control: no-store）：授权页 URL 稳定，
    若浏览器缓存旧版 HTML，已部署的自动登录/绑定逻辑将永不执行，
    用户反复看到旧登录表单。
    """
    # 注：返回显式 HTMLResponse 会覆盖注入 response 的 headers，
    # 因此必须把缓存控制头显式传给每个返回的响应
    no_cache_headers = {"Cache-Control": "no-store", "Pragma": "no-cache"}

    client = (
        db.query(ConnectClientModel)
        .filter(ConnectClientModel.client_id == client_id)
        .first()
    )
    if client is None:
        return HTMLResponse(
            _error_page("未知的客户端 ID"), status_code=400, headers=no_cache_headers
        )
    if client.redirect_uri != redirect_uri:
        return HTMLResponse(
            _error_page("回调地址与注册值不一致，请重新发起添加"),
            status_code=400,
            headers=no_cache_headers,
        )
    if len(code_challenge) < 43 or len(state) > 512:
        return HTMLResponse(
            _error_page("参数不合法"), status_code=400, headers=no_cache_headers
        )

    # 模板含 CSS 花括号，不能用 str.format，改用占位符替换
    page = _AUTHORIZE_PAGE_TEMPLATE.replace(
        "__CLIENT_NAME__", html.escape(client.client_name or client_id)
    ).replace("__REDIRECT_URI__", html.escape(client.redirect_uri))
    return HTMLResponse(page, headers=no_cache_headers)


def _error_page(message: str) -> str:
    """授权流程出错时的简单提示页（与授权页同风格：Arco Design 浅色）。"""
    return (
        "<!DOCTYPE html><html lang='zh-CN'><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width, initial-scale=1'>"
        "<title>授权失败</title><style>"
        "body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;"
        "background:#F2F3F5;color:#1D2129;display:flex;align-items:center;"
        "justify-content:center;min-height:100vh;margin:0;padding:16px}"
        ".box{background:#fff;border:1px solid #E5E6EB;border-radius:8px;"
        "padding:28px 24px;max-width:400px;width:100%;"
        "box-shadow:0 4px 12px rgba(0,0,0,.06)}"
        "h1{font-size:16px;font-weight:600;margin:0 0 8px;color:#F53F3F;"
        "display:flex;align-items:center;gap:8px}"
        "p{color:#4E5969;font-size:14px;line-height:1.6;margin:0 0 16px;"
        "word-break:break-all}"
        "a{color:#165DFF;font-size:14px;text-decoration:none}"
        "a:hover{text-decoration:underline}"
        "</style></head><body><div class='box'><h1>"
        "<svg viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' "
        "stroke-linecap='round' stroke-linejoin='round' width='18' height='18' "
        "aria-hidden='true'><path d='M12 3l10 18H2L12 3z'/>"
        "<path d='M12 10v4'/><path d='M12 17h.01'/></svg>授权失败</h1>"
        f"<p>{html.escape(message)}</p>"
        "<a href='/docs'>返回管理页面</a>"
        "</div></body></html>"
    )


@router.post("/confirm")
def confirm(
    request: Request,
    db: Session = Depends(get_db),
    client_id: str = Form(...),
    redirect_uri: str = Form(...),
    state: str = Form(""),
    code_challenge: str = Form(...),
):
    """确认授权：会话鉴权后生成一次性授权码，302 回跳源 app。

    授权页以原生表单 POST 提交，故使用 Form 参数而非 JSON Body。
    """
    _cleanup_expired(db)
    session_record = _require_session(db, _get_session_token(request))
    if session_record is None:
        raise HTTPException(status_code=401, detail="请先登录")

    client = (
        db.query(ConnectClientModel)
        .filter(ConnectClientModel.client_id == client_id)
        .first()
    )
    if client is None:
        raise HTTPException(status_code=400, detail="未知的客户端 ID")
    if client.redirect_uri != redirect_uri:
        raise HTTPException(status_code=400, detail="回调地址与注册值不一致")

    code = secrets.token_hex(24)
    db.add(
        ConnectAuthCodeModel(
            code=code,
            client_id=client.client_id,
            redirect_uri=client.redirect_uri,
            state=state,
            code_challenge=code_challenge,
            expires_at=time.time() + CODE_TTL_SECONDS,
        )
    )
    db.commit()

    separator = "&" if "?" in client.redirect_uri else "?"
    callback = f"{client.redirect_uri}{separator}code={code}"
    if state:
        callback += f"&state={state}"
    return RedirectResponse(url=callback, status_code=302)


# ================================================================
# Token 交换（源 app 跨域调用）：签发独立 apikey
# ================================================================


@router.post("/token")
def token(data: TokenRequest, db: Session = Depends(get_db)):
    """用授权码 + PKCE verifier 换取独立 apikey。

    - 授权码一次性使用，用后即删
    - SHA-256(code_verifier) 必须与授权时的 code_challenge 一致
    - 签发的 key 为全新独立 key（note 记录来源回调地址），
      与现有共享 apikey 完全分离，可单独撤销
    """
    _cleanup_expired(db)

    record = (
        db.query(ConnectAuthCodeModel)
        .filter(ConnectAuthCodeModel.code == data.code)
        .first()
    )
    if record is None:
        raise HTTPException(status_code=400, detail="授权码无效或已过期")
    if record.client_id != data.client_id:
        raise HTTPException(status_code=400, detail="授权码不属于该客户端")

    verifier_hash = hashlib.sha256(data.code_verifier.encode()).hexdigest()
    if verifier_hash != record.code_challenge:
        raise HTTPException(status_code=400, detail="PKCE 校验失败")

    # 全部校验通过后，一次性使用授权码并签发独立 apikey，
    # note 记录来源，便于管理页识别与单独撤销
    db.delete(record)
    new_key_str = str(uuid.uuid4().hex)
    db.add(APIKeyModel(key=new_key_str, note=f"connect: {record.redirect_uri}"))
    db.commit()

    return {"apikey": new_key_str}

    # 签发独立 apikey，note 记录来源，便于管理页识别与单独撤销
    new_key_str = str(uuid.uuid4().hex)
    db.add(APIKeyModel(key=new_key_str, note=f"connect: {record.redirect_uri}"))
    db.commit()

    return {"apikey": new_key_str}
