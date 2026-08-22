from fastapi import (
    APIRouter,
    Body,
    Depends,
    File,
    HTTPException,
    Request,
    Response,
    UploadFile,
)
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field, field_validator
from typing import List, Dict, Any, Optional
from sqlalchemy import or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
import json
import os
import uuid
import requests
from app.core.security import get_api_key, hash_password, verify_admin_credentials
from app.core import oidc
from app.core.crypto import decrypt, encrypt
from app.core.config import (
    ADMIN_USER,
    AVATAR_UPLOAD_DIR,
    MAX_AVATAR_SIZE,
    ALLOWED_AVATAR_TYPES,
)
from app.db.database import get_db
from app.db.models import (
    APIKeyModel,
    AdminCredentialModel,
    OIDCIdentityModel,
    ClusterNode,
    ServerListModel,
    UserProfileModel,
)
from app.services.email_service import (
    EmailConfigurationError,
    EmailDeliveryError,
    get_smtp_config_status,
    save_smtp_settings,
    send_email,
)
from app.routers.connect import create_connect_session

router = APIRouter(prefix="/admin", tags=["admin"])


class OIDCExchangeRequest(BaseModel):
    """前端授权码 + PKCE 参数；令牌仅在服务端交换。"""

    code: str = Field(min_length=1, max_length=4096)
    code_verifier: str = Field(min_length=43, max_length=128)
    nonce: str = Field(min_length=16, max_length=256)
    redirect_uri: str = Field(min_length=1, max_length=2048)


class ChangePasswordRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=256)
    new_password: str = Field(min_length=8, max_length=256)


class SendEmailRequest(BaseModel):
    recipients: List[str] = Field(min_length=1, max_length=100)
    subject: str = Field(min_length=1, max_length=255)
    text_body: str = Field(min_length=1, max_length=100000)
    html_body: Optional[str] = Field(default=None, max_length=100000)

    @field_validator("recipients")
    def validate_recipients(cls, recipients: List[str]) -> List[str]:
        """拒绝空地址及可能造成邮件头注入的地址。"""
        for recipient in recipients:
            address = recipient.strip()
            if (
                not address
                or "\r" in address
                or "\n" in address
                or address.count("@") != 1
                or address.startswith("@")
                or address.endswith("@")
            ):
                raise ValueError("收件人邮箱地址格式不正确")
        return [recipient.strip() for recipient in recipients]


class SMTPSettingsRequest(BaseModel):
    """SMTP 配置请求体。密码字段可选——留空表示不修改已存储的密码。"""

    host: str = Field(default="", max_length=255)
    port: int = Field(default=587, ge=1, le=65535)
    username: str = Field(default="", max_length=255)
    password: str = Field(default="", max_length=255)
    from_email: str = Field(default="", max_length=255)
    from_name: str = Field(default="Mobile Portainer", max_length=255)
    use_ssl: bool = False
    use_starttls: bool = True
    timeout: int = Field(default=10, ge=1, le=120)


class UserProfileRequest(BaseModel):
    """用户个人信息请求体。"""

    display_name: str = Field(default="", max_length=128)
    email: str = Field(default="", max_length=255)
    avatar: str = Field(default="", max_length=2048)
    bio: str = Field(default="", max_length=1024)

    @field_validator("email")
    def validate_email(cls, email: str) -> str:
        if email and ("\r" in email or "\n" in email or email.count("@") != 1):
            raise ValueError("邮箱地址格式不正确")
        return email.strip()


@router.get("/oidc/config")
def get_oidc_config():
    """返回启动 OIDC 授权码流程所需的非敏感配置。"""
    try:
        return oidc.public_config()
    except oidc.OIDCError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@router.post("/oidc/exchange")
def exchange_oidc_code(data: OIDCExchangeRequest, response: Response, db: Session = Depends(get_db)):
    """验证外部 IdP 身份后签发或复用仅属于该 subject 的 API Key。"""
    try:
        identity = oidc.exchange_code_for_identity(
            code=data.code,
            code_verifier=data.code_verifier,
            nonce=data.nonce,
            redirect_uri=data.redirect_uri,
        )
    except oidc.OIDCError as exc:
        status_code = 400 if "回调地址" in str(exc) else 401
        raise HTTPException(status_code=status_code, detail=str(exc)) from exc

    subject = str(identity["sub"])
    display_name = str(identity.get("preferred_username") or identity.get("name") or subject)
    note = f"OIDC: {display_name} ({subject})"
    identity_record = (
        db.query(OIDCIdentityModel)
        .filter(OIDCIdentityModel.issuer == oidc.OIDC_ISSUER, OIDCIdentityModel.subject == subject)
        .first()
    )
    api_key = db.get(APIKeyModel, identity_record.api_key_id) if identity_record else None
    if api_key is None:
        # 唯一约束让同一 subject 的并发首次登录只创建一条身份映射；
        # 输掉竞争的请求回滚后复用已提交的 API Key。
        try:
            api_key = APIKeyModel(key=uuid.uuid4().hex, note=note)
            db.add(api_key)
            db.flush()
            db.add(
                OIDCIdentityModel(
                    issuer=oidc.OIDC_ISSUER,
                    subject=subject,
                    api_key_id=api_key.id,
                )
            )
            db.commit()
            db.refresh(api_key)
        except IntegrityError:
            db.rollback()
            identity_record = (
                db.query(OIDCIdentityModel)
                .filter(
                    OIDCIdentityModel.issuer == oidc.OIDC_ISSUER,
                    OIDCIdentityModel.subject == subject,
                )
                .one()
            )
            api_key = db.get(APIKeyModel, identity_record.api_key_id)
            if api_key is None:
                raise HTTPException(status_code=500, detail="OIDC 身份映射数据不完整")
    if api_key is None:
        raise HTTPException(status_code=500, detail="OIDC 身份映射数据不完整")
    if api_key.note != note:
        # 显示名变动不改变外部 subject 对应的权限，仅更新可读备注。
        api_key.note = note
        db.commit()

    # OIDC 用户默认获得当前单管理员模型的管理权限，并让 /connect 流程复用登录会话。
    create_connect_session(db, response)
    return {
        "api_key": api_key.key,
        "id": api_key.id,
        "note": api_key.note,
        "subject": subject,
        "authentication_method": "oidc",
    }


@router.post("/login")
def login(request: Request, response: Response, db: Session = Depends(get_db)):
    admin_user = request.headers.get("X-Admin-User")
    admin_pass = request.headers.get("X-Admin-Pass")
    if not verify_admin_credentials(db, admin_user, admin_pass):
        raise HTTPException(status_code=401, detail="Invalid Admin Credentials")

    # 与 /connect 授权流程打通：同步创建会话并种 connect_session cookie，
    # 跳转授权页（/connect/authorize）时无需重复输入用户名密码
    create_connect_session(db, response)

    # 查找已有的 API key，没有则自动创建
    api_key = db.query(APIKeyModel).first()
    if not api_key:
        new_key_str = str(uuid.uuid4().hex)
        api_key = APIKeyModel(key=new_key_str, note="自动创建")
        db.add(api_key)
        db.commit()
        db.refresh(api_key)

    return {"api_key": api_key.key, "id": api_key.id, "note": api_key.note}


@router.post("/password")
def change_password(data: ChangePasswordRequest, db: Session = Depends(get_db)):
    """校验当前管理员密码后，持久化保存新的密码哈希。"""
    if not verify_admin_credentials(db, ADMIN_USER, data.current_password):
        raise HTTPException(status_code=401, detail="当前密码不正确")

    credential = db.get(AdminCredentialModel, 1)
    password_hash = hash_password(data.new_password)
    if credential:
        credential.password_hash = password_hash
    else:
        db.add(AdminCredentialModel(id=1, password_hash=password_hash))
    db.commit()
    return {"message": "密码修改成功"}


@router.get("/email/config", dependencies=[Depends(get_api_key)])
def get_email_config(db: Session = Depends(get_db)):
    """获取 SMTP 配置状态；永不返回 SMTP 密码。"""
    return get_smtp_config_status(db)


@router.put("/email/config", dependencies=[Depends(get_api_key)])
def update_email_config(data: SMTPSettingsRequest, db: Session = Depends(get_db)):
    """保存或更新 SMTP 邮箱配置，持久化到数据库。密码会加密存储。"""
    try:
        save_smtp_settings(db, data.dict(exclude_unset=True))
    except Exception as exc:
        raise HTTPException(
            status_code=500, detail=f"保存 SMTP 配置失败: {exc}"
        ) from exc
    return {"message": "SMTP 配置已保存", "config": get_smtp_config_status(db)}


@router.post("/email/send", dependencies=[Depends(get_api_key)])
def send_email_to_users(data: SendEmailRequest, db: Session = Depends(get_db)):
    """向指定收件人发送文本或 HTML 邮件。"""
    try:
        send_email(data.recipients, data.subject, data.text_body, data.html_body, db=db)
    except EmailConfigurationError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except EmailDeliveryError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    return {"message": "邮件发送成功", "recipient_count": len(data.recipients)}


@router.post("/email/test", dependencies=[Depends(get_api_key)])
def send_test_email_to_users(data: SendEmailRequest, db: Session = Depends(get_db)):
    """向指定收件人发送文本或 HTML 邮件。"""
    try:
        send_email(data.recipients, data.subject, data.text_body, data.html_body, db=db)
    except EmailConfigurationError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except EmailDeliveryError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    return {"message": "邮件发送成功", "recipient_count": len(data.recipients)}


@router.get("/keys", dependencies=[Depends(get_api_key)])
def list_keys(db: Session = Depends(get_db)):
    result = db.query(APIKeyModel).all()
    return result


@router.post("/keys", dependencies=[Depends(get_api_key)])
def add_key(data: Dict[str, Any], db: Session = Depends(get_db)):
    new_key_str = data.get("key") or str(uuid.uuid4().hex)
    existing = db.query(APIKeyModel).filter(APIKeyModel.key == new_key_str).first()
    if existing:
        raise HTTPException(status_code=400, detail="Key already exists")

    new_key = APIKeyModel(key=new_key_str, note=data.get("note"))
    db.add(new_key)
    db.commit()
    db.refresh(new_key)

    targets: Optional[List[str]] = data.get("targets")
    apply_all: bool = bool(data.get("apply_all"))
    if apply_all:
        nodes = db.query(ClusterNode).all()
    elif targets:
        nodes = db.query(ClusterNode).filter(ClusterNode.id.in_(targets)).all()
    else:
        nodes = []

    results: List[Dict[str, Any]] = []
    for n in nodes:
        try:
            r = requests.post(
                f"{n.base_url.rstrip('/')}/admin/keys",
                headers={"X-Admin-User": n.admin_user, "X-Admin-Pass": n.admin_pass},
                json={"key": new_key.key, "note": new_key.note},
                timeout=10,
            )
            results.append({"node": n.name, "status": r.status_code})
        except Exception as e:
            results.append({"node": n.name, "error": str(e)})

    return {"key": new_key, "propagation": results}


@router.delete("/keys/{key_str}", dependencies=[Depends(get_api_key)])
def delete_key(key_str: str, db: Session = Depends(get_db)):
    # 兼容按 id（Flutter 端）或按 key（Web 端）两种传参删除
    key = (
        db.query(APIKeyModel)
        .filter(or_(APIKeyModel.id == key_str, APIKeyModel.key == key_str))
        .first()
    )
    if not key:
        raise HTTPException(status_code=404, detail="Key not found")
    db.delete(key)
    db.commit()
    return {"status": "deleted"}


@router.delete("/keys/{key_str}/propagate", dependencies=[Depends(get_api_key)])
def delete_key_propagate(
    key_str: str, data: Dict[str, Any], db: Session = Depends(get_db)
):
    targets: Optional[List[str]] = data.get("targets")
    apply_all: bool = bool(data.get("apply_all"))
    if apply_all:
        nodes = db.query(ClusterNode).all()
    elif targets:
        nodes = db.query(ClusterNode).filter(ClusterNode.id.in_(targets)).all()
    else:
        nodes = []

    results: List[Dict[str, Any]] = []
    for n in nodes:
        try:
            r = requests.delete(
                f"{n.base_url.rstrip('/')}/admin/keys/{key_str}",
                headers={"X-Admin-User": n.admin_user, "X-Admin-Pass": n.admin_pass},
                timeout=10,
            )
            results.append({"node": n.name, "status": r.status_code})
        except Exception as e:
            results.append({"node": n.name, "error": str(e)})
    return {"status": "deleted", "propagation": results}


@router.get("/servers", dependencies=[Depends(get_api_key)])
def get_servers(db: Session = Depends(get_db)):
    """获取 Web 端服务器列表（apiKey 解密返回）。

    服务器列表存数据库而非浏览器 localStorage，保证同一实例的所有访问入口
    （不同 origin）共享同一份数据。
    """
    record = db.get(ServerListModel, 1)
    if not record or not record.servers_json:
        return []
    servers = json.loads(record.servers_json)
    for s in servers:
        if s.get("apiKey"):
            s["apiKey"] = decrypt(s["apiKey"])
    return servers


@router.put("/servers", dependencies=[Depends(get_api_key)])
def save_servers(data: Any = Body(None), db: Session = Depends(get_db)):
    """全量保存 Web 端服务器列表；apiKey 加密存储，读取时解密。"""
    if not isinstance(data, list):
        raise HTTPException(status_code=400, detail="请求体必须是 JSON 数组")

    record = db.get(ServerListModel, 1)
    if record is None:
        record = ServerListModel(id=1)
        db.add(record)

    servers = []
    for s in data:
        api_key = str(s.get("apiKey") or "")
        servers.append(
            {
                "name": str(s.get("name") or ""),
                "url": str(s.get("url") or ""),
                "apiKey": encrypt(api_key) if api_key else "",
                "ignoreSsl": str(s.get("ignoreSsl") or "false"),
            }
        )
    record.servers_json = json.dumps(servers, ensure_ascii=False)
    db.commit()
    return {"message": "服务器列表已保存", "count": len(servers)}


@router.get("/nodes", dependencies=[Depends(get_api_key)])
def list_nodes(db: Session = Depends(get_db)):
    return db.query(ClusterNode).all()


@router.post("/nodes", dependencies=[Depends(get_api_key)])
def add_node(data: Dict[str, Any], db: Session = Depends(get_db)):
    name = data.get("name")
    base_url = data.get("base_url")
    admin_user = data.get("admin_user")
    admin_pass = data.get("admin_pass")
    if not all([name, base_url, admin_user, admin_pass]):
        raise HTTPException(status_code=400, detail="Missing fields")
    existing = db.query(ClusterNode).filter(ClusterNode.name == name).first()
    if existing:
        raise HTTPException(status_code=400, detail="Node name exists")

    node = ClusterNode(
        name=name, base_url=base_url, admin_user=admin_user, admin_pass=admin_pass
    )
    db.add(node)
    db.commit()
    db.refresh(node)
    return node


@router.delete("/nodes/{node_id}", dependencies=[Depends(get_api_key)])
def delete_node(node_id: str, db: Session = Depends(get_db)):
    node = db.query(ClusterNode).filter(ClusterNode.id == node_id).first()
    if not node:
        raise HTTPException(status_code=404, detail="Node not found")
    db.delete(node)
    db.commit()
    return {"status": "deleted"}


@router.get("/profile", dependencies=[Depends(get_api_key)])
def get_profile(db: Session = Depends(get_db)):
    """获取当前用户个人信息。"""
    profile = db.get(UserProfileModel, 1)
    if not profile:
        return {
            "display_name": "",
            "email": "",
            "avatar": "",
            "bio": "",
        }
    return {
        "display_name": profile.display_name or "",
        "email": profile.email or "",
        "avatar": profile.avatar or "",
        "bio": profile.bio or "",
        "updated_at": profile.updated_at.isoformat() if profile.updated_at else None,
    }


@router.put("/profile", dependencies=[Depends(get_api_key)])
def update_profile(data: UserProfileRequest, db: Session = Depends(get_db)):
    """更新用户个人信息。仅更新请求中显式传入的字段。"""
    profile = db.get(UserProfileModel, 1)
    if profile is None:
        profile = UserProfileModel(id=1)
        db.add(profile)

    update_data = data.dict(exclude_unset=True)
    for field in ("display_name", "email", "avatar", "bio"):
        if field in update_data:
            setattr(profile, field, update_data[field] or None)

    db.commit()
    db.refresh(profile)
    return {
        "message": "个人信息已更新",
        "profile": {
            "display_name": profile.display_name or "",
            "email": profile.email or "",
            "avatar": profile.avatar or "",
            "bio": profile.bio or "",
            "updated_at": profile.updated_at.isoformat(),
        },
    }


@router.post("/profile/avatar", dependencies=[Depends(get_api_key)])
async def upload_avatar(file: UploadFile = File(...), db: Session = Depends(get_db)):
    """上传用户头像。支持 PNG、JPEG、GIF、WebP 格式，最大 2MB。"""
    # 1. 校验文件类型
    if file.content_type not in ALLOWED_AVATAR_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"不支持的文件类型 '{file.content_type}'，仅允许 {', '.join(ALLOWED_AVATAR_TYPES)}",
        )

    # 2. 读取文件内容并校验大小
    contents = await file.read()
    if len(contents) > MAX_AVATAR_SIZE:
        max_mb = MAX_AVATAR_SIZE / (1024 * 1024)
        raise HTTPException(
            status_code=400,
            detail=f"文件大小超过限制（最大 {max_mb:.0f}MB）",
        )

    # 3. 确保上传目录存在
    os.makedirs(AVATAR_UPLOAD_DIR, exist_ok=True)

    # 4. 生成唯一文件名并保存
    ext = _get_avatar_extension(file.content_type)
    filename = f"{uuid.uuid4().hex}{ext}"
    filepath = os.path.join(AVATAR_UPLOAD_DIR, filename)
    with open(filepath, "wb") as f:
        f.write(contents)

    # 5. 更新用户 profile 中的 avatar 字段（存储相对路径 URL）
    avatar_url = f"/static/avatars/{filename}"
    profile = db.get(UserProfileModel, 1)
    if profile is None:
        profile = UserProfileModel(id=1)
        db.add(profile)
    profile.avatar = avatar_url
    db.commit()

    return {
        "message": "头像上传成功",
        "avatar_url": avatar_url,
    }


def _get_avatar_extension(content_type: str) -> str:
    """根据 MIME 类型返回对应的文件扩展名。"""
    mapping = {
        "image/png": ".png",
        "image/jpeg": ".jpg",
        "image/gif": ".gif",
        "image/webp": ".webp",
    }
    return mapping.get(content_type, ".png")


# HTML Page (We can keep this here or in main.py, but better here for organization)
# However, this endpoint is at root "/" so we should define it in main.py or include it here with prefix=""
# I'll put the admin page in a separate router or just here but with prefix ""
# Let's create a separate router for the UI or just put it in main.py for simplicity as it is the landing page.
# Actually, the user asked to split main.py. So let's put it in a separate file app/routers/web_ui.py
