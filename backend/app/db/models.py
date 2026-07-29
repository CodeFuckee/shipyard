from sqlalchemy import Column, String, DateTime, Integer, Text, Float
from datetime import datetime
import uuid
from .database import Base


class APIKeyModel(Base):
    __tablename__ = "api_keys"
    id = Column(String, primary_key=True, index=True, default=lambda: str(uuid.uuid4()))
    key = Column(String, unique=True, index=True)
    note = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class ClusterNode(Base):
    __tablename__ = "cluster_nodes"
    id = Column(String, primary_key=True, index=True, default=lambda: str(uuid.uuid4()))
    name = Column(String, unique=True, index=True)
    base_url = Column(String)
    admin_user = Column(String)
    admin_pass = Column(String)
    created_at = Column(DateTime, default=datetime.utcnow)


class AdminCredentialModel(Base):
    """管理员密码哈希；固定使用 id=1 的单条配置记录。"""

    __tablename__ = "admin_credentials"

    id = Column(Integer, primary_key=True, default=1)
    password_hash = Column(String, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class SMTPSettingsModel(Base):
    """SMTP 邮箱配置；固定使用 id=1 的单条配置记录。密码经过加密存储。"""

    __tablename__ = "smtp_settings"

    id = Column(Integer, primary_key=True, default=1)
    host = Column(String, nullable=True)
    port = Column(Integer, nullable=True)
    username = Column(String, nullable=True)
    encrypted_password = Column(String, nullable=True)  # 加密后的 SMTP 密码
    from_email = Column(String, nullable=True)
    from_name = Column(String, nullable=True)
    use_ssl = Column(Integer, default=0)  # 0/1 布尔标记
    use_starttls = Column(Integer, default=1)
    timeout = Column(Integer, default=10)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class UserProfileModel(Base):
    """用户个人信息；固定使用 id=1 的单条配置记录。"""

    __tablename__ = "user_profile"

    id = Column(Integer, primary_key=True, default=1)
    display_name = Column(String, nullable=True)  # 显示名称（昵称）
    email = Column(String, nullable=True)  # 联系邮箱
    avatar = Column(String, nullable=True)  # 头像 URL 或 base64
    bio = Column(String, nullable=True)  # 个人简介
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class OAuthClientModel(Base):
    """OAuth 2.0 动态注册的客户端。"""

    __tablename__ = "oauth_clients"

    id = Column(Integer, primary_key=True, autoincrement=True)
    client_id = Column(String, unique=True, index=True, nullable=False)
    client_secret = Column(String, nullable=True)  # auth_method="none" 时为 None
    client_id_issued_at = Column(Integer, nullable=False)
    client_secret_expires_at = Column(Integer, nullable=True)  # None = 永不过期
    redirect_uris = Column(Text, nullable=True)  # JSON 数组字符串
    token_endpoint_auth_method = Column(String, default="client_secret_post")
    grant_types = Column(Text, nullable=False)  # JSON 数组字符串
    response_types = Column(Text, nullable=False)  # JSON 数组字符串
    scope = Column(String, nullable=True)
    client_name = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class OAuthAuthorizationCodeModel(Base):
    """OAuth 2.0 授权码 — 一次性使用，10 分钟有效期。"""

    __tablename__ = "oauth_auth_codes"

    id = Column(Integer, primary_key=True, autoincrement=True)
    code = Column(String, unique=True, index=True, nullable=False)
    client_id = Column(String, index=True, nullable=False)
    scopes = Column(Text, nullable=True)  # JSON 数组字符串
    expires_at = Column(Float, nullable=False)
    redirect_uri = Column(String, nullable=False)
    code_challenge = Column(String, nullable=False)
    redirect_uri_provided_explicitly = Column(Integer, default=0)
    resource = Column(String, nullable=True)
    subject = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class OAuthTokenModel(Base):
    """OAuth 2.0 Token — access token 和 refresh token 共用表。"""

    __tablename__ = "oauth_tokens"

    id = Column(Integer, primary_key=True, autoincrement=True)
    token = Column(String, unique=True, index=True, nullable=False)
    token_type = Column(String, nullable=False)  # "access" 或 "refresh"
    client_id = Column(String, index=True, nullable=False)
    scopes = Column(Text, nullable=True)  # JSON 数组字符串
    expires_at = Column(Integer, nullable=True)  # Unix 时间戳
    resource = Column(String, nullable=True)
    subject = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class ProjectModel(Base):
    """Docker 项目管理 — 关联 Dockerfile / docker-compose.yaml 构建与部署。"""

    __tablename__ = "projects"

    id = Column(
        String,
        primary_key=True,
        index=True,
        default=lambda: f"proj_{uuid.uuid4().hex[:12]}",
    )
    name = Column(String, unique=True, index=True, nullable=False)
    description = Column(String, nullable=True)
    status = Column(
        String, default="idle", nullable=False
    )  # idle | building | running | failed
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
