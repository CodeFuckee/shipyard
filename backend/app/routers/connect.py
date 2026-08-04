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
# JS 流程：查会话 → 已登录显示确认按钮 / 未登录显示登录表单 →
# 确认后 POST /connect/confirm，后端 302 回跳携带一次性 code。
_AUTHORIZE_PAGE_TEMPLATE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>授权添加服务器</title>
<style>
  :root { color-scheme: light dark; }
  body {
    margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
    background: #0f172a; color: #e2e8f0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  }
  .card {
    width: min(420px, 92vw); background: #1e293b; border-radius: 16px;
    padding: 32px 28px; box-shadow: 0 20px 60px rgba(0,0,0,.4);
  }
  h1 { font-size: 20px; margin: 0 0 8px; }
  .sub { color: #94a3b8; font-size: 14px; margin-bottom: 20px; }
  .warn {
    background: rgba(239, 68, 68, .12); border: 1px solid rgba(239, 68, 68, .4);
    color: #fca5a5; border-radius: 10px; padding: 12px 14px; font-size: 13px; margin-bottom: 20px;
  }
  .field { margin-bottom: 14px; }
  label { display: block; font-size: 13px; color: #94a3b8; margin-bottom: 6px; }
  input {
    width: 100%; box-sizing: border-box; padding: 10px 12px; border-radius: 8px;
    border: 1px solid #334155; background: #0f172a; color: #e2e8f0; font-size: 14px;
  }
  input:focus { outline: none; border-color: #3b82f6; }
  button {
    width: 100%; padding: 12px; border: none; border-radius: 10px;
    background: #3b82f6; color: white; font-size: 15px; font-weight: 600;
    cursor: pointer; margin-top: 6px;
  }
  button:disabled { opacity: .6; cursor: not-allowed; }
  button.ghost { background: #334155; margin-top: 10px; }
  .err { color: #f87171; font-size: 13px; margin-top: 10px; min-height: 18px; }
  .info { font-size: 13px; color: #94a3b8; margin-top: 16px; line-height: 1.6; }
  .info b { color: #e2e8f0; word-break: break-all; }
</style>
</head>
<body>
<div class="card">
  <h1>授权添加服务器</h1>
  <div class="sub">此页面由目标服务器自身提供，请确认以下信息</div>

  <div class="warn">
    点击确认后，本服务器将向下方<b>回调地址</b>签发一把<b>管理员级 API 密钥</b>。
    请确认这是你正在添加的服务器，谨防仿冒页面。
  </div>

  <div class="info">
    请求方：<b>__CLIENT_NAME__</b><br>
    回调地址：<b>__REDIRECT_URI__</b>
  </div>

  <div id="confirmBox" style="display:none">
    <button id="btnConfirm">确认并添加</button>
    <button class="ghost" id="btnCancel">取消</button>
  </div>

  <div id="loginBox" style="display:none">
    <div class="field">
      <label>用户名</label>
      <input id="username" autocomplete="username">
    </div>
    <div class="field">
      <label>密码</label>
      <input id="password" type="password" autocomplete="current-password">
    </div>
    <button id="btnLogin">登录</button>
    <div class="err" id="err"></div>
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

  fetch('/connect/session', {credentials: 'same-origin'})
    .then(function(r) { return r.json(); })
    .then(function(s) {
      if (s.logged_in) {
        document.getElementById('confirmBox').style.display = 'block';
      } else {
        document.getElementById('loginBox').style.display = 'block';
      }
    });

  document.getElementById('btnConfirm').addEventListener('click', submitConfirm);

  document.getElementById('btnCancel').addEventListener('click', function() {
    document.getElementById('confirmBox').style.display = 'none';
    var div = document.createElement('div');
    div.className = 'warn';
    div.textContent = '已取消授权，可以关闭此页面。';
    document.querySelector('.card').appendChild(div);
  });

  document.getElementById('btnLogin').addEventListener('click', function() {
    var btn = this; btn.disabled = true;
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
    }).finally(function() { btn.disabled = false; });
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
    """交互式授权页。校验回调地址与注册值一致后渲染授权页面。"""
    client = (
        db.query(ConnectClientModel)
        .filter(ConnectClientModel.client_id == client_id)
        .first()
    )
    if client is None:
        return HTMLResponse(_error_page("未知的客户端 ID"), status_code=400)
    if client.redirect_uri != redirect_uri:
        return HTMLResponse(
            _error_page("回调地址与注册值不一致，请重新发起添加"),
            status_code=400,
        )
    if len(code_challenge) < 43 or len(state) > 512:
        return HTMLResponse(_error_page("参数不合法"), status_code=400)

    # 模板含 CSS 花括号，不能用 str.format，改用占位符替换
    page = _AUTHORIZE_PAGE_TEMPLATE.replace(
        "__CLIENT_NAME__", html.escape(client.client_name or client_id)
    ).replace("__REDIRECT_URI__", html.escape(client.redirect_uri))
    return HTMLResponse(page)


def _error_page(message: str) -> str:
    """授权流程出错时的简单提示页。"""
    return (
        "<!DOCTYPE html><html lang='zh-CN'><head><meta charset='utf-8'>"
        "<title>授权失败</title><style>body{font-family:sans-serif;"
        "background:#0f172a;color:#e2e8f0;display:flex;align-items:center;"
        "justify-content:center;height:100vh;margin:0}"
        ".box{background:#1e293b;padding:32px;border-radius:16px;max-width:400px}"
        "h1{font-size:18px;color:#f87171}p{color:#94a3b8;font-size:14px}"
        "</style></head><body><div class='box'><h1>授权失败</h1>"
        f"<p>{html.escape(message)}</p>"
        "<p><a href='/docs' style='color:#3b82f6'>返回管理页面</a></p>"
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
