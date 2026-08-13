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


class AIProviderModel(Base):
    """AI API 供应商配置 — 多行记录，每个供应商一行。

    API Key 经 crypto.encrypt 加密后存储（encrypted_api_key），
    任何接口响应均不返回明文 Key。
    """

    __tablename__ = "ai_providers"

    id = Column(String, primary_key=True, index=True, default=lambda: str(uuid.uuid4()))
    name = Column(String, unique=True, index=True, nullable=False)  # 供应商显示名（唯一）
    provider_type = Column(String, default="custom", nullable=False)  # deepseek | openai | custom
    base_url = Column(String, nullable=False)  # OpenAI 兼容 API 基础地址
    encrypted_api_key = Column(String, nullable=True)  # 加密后的 API Key
    default_model = Column(String, nullable=True)  # 默认模型名
    enabled = Column(Integer, default=1)  # 0/1 是否启用
    is_default = Column(Integer, default=0)  # 0/1 默认供应商（hermes 未配置时 agent 回退用）
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class AgentChatLogModel(Base):
    """AI Agent 调试日志 — 每次对话一行（issue #24）。

    LLM 配置来源、工具调用步骤与事件序列、完整请求消息与最终回复
    均保存为 JSON 文本列，供设置页「AI 调试日志」查看；写入后自动
    清理，仅保留最近 100 条（见 app/agent/debug_log.py）。
    """

    __tablename__ = "agent_chat_logs"

    id = Column(String, primary_key=True, index=True, default=lambda: str(uuid.uuid4()))
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    request_text = Column(String, nullable=True)  # 列表摘要：最后一条用户消息
    llm_source = Column(String, nullable=True)  # hermes | provider
    llm_name = Column(String, nullable=True)  # Hermes / 供应商显示名
    llm_model = Column(String, nullable=True)  # 实际使用的模型名
    tools_names = Column(Text, nullable=True)  # JSON 数组：本次启用的工具
    status = Column(String, nullable=False, default="success")  # success | error
    error_message = Column(Text, nullable=True)  # 失败原因（status=error 时）
    duration_ms = Column(Integer, default=0)  # 本次对话总耗时（毫秒）
    messages_json = Column(Text, nullable=True)  # 完整请求消息（对话情况）
    events_json = Column(Text, nullable=True)  # 步骤/工具调用事件序列
    reply_text = Column(Text, nullable=True)  # 最终回复全文


class ServerListModel(Base):
    """Web 端服务器列表；固定使用 id=1 的单条配置记录。

    服务器列表存后端数据库而非浏览器 localStorage，使同一实例的所有
    访问入口（不同 origin，如 http://10.0.0.169:8080 与
    https://home.chenkaidi.top:507）共享同一份数据。
    servers_json 中的 apiKey 经 crypto.encrypt 加密后存储。
    """

    __tablename__ = "server_list"

    id = Column(Integer, primary_key=True, default=1)
    servers_json = Column(Text, nullable=True)  # 加密 apiKey 后的 JSON 数组
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


class HermesConfigModel(Base):
    """Hermes 接入配置 — 固定使用 id=1 的单条配置记录。

    前端设置页保存的配置，优先级高于环境变量（HERMES_BASE_URL 等），
    保存后立即生效无需重启。API Key 经 crypto.encrypt 加密后存储
    （encrypted_api_key），任何接口响应均不返回明文 Key。
    """

    __tablename__ = "hermes_config"

    id = Column(Integer, primary_key=True, default=1)
    base_url = Column(String, nullable=True)  # 实例地址（如 https://hermes.example.com/v1），空 = 未启用
    encrypted_api_key = Column(String, nullable=True)  # 加密后的 API Key
    model = Column(String, nullable=True)  # 默认模型名
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


class ConnectClientModel(Base):
    """/connect 授权流程的动态注册客户端（public client，无 secret）。

    源 app（任意自托管 Flutter Web 部署）在跳转前注册自己的回调地址，
    authorize 阶段校验 redirect_uri 与注册值一致，防止授权码被转发。
    """

    __tablename__ = "connect_clients"

    id = Column(Integer, primary_key=True, autoincrement=True)
    client_id = Column(String, unique=True, index=True, nullable=False)
    client_name = Column(String, nullable=True)  # 源 app 自定义名称，授权页展示
    redirect_uri = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)


class ConnectSessionModel(Base):
    """/connect 授权流程的登录会话（cookie）。

    与现有无状态 X-API-Key 认证分离：仅用于授权页"已登录"判定
    及确认动作的鉴权，不参与普通 API 调用。
    """

    __tablename__ = "connect_sessions"

    id = Column(Integer, primary_key=True, autoincrement=True)
    session_token = Column(String, unique=True, index=True, nullable=False)
    expires_at = Column(Float, nullable=False)  # Unix 时间戳
    created_at = Column(DateTime, default=datetime.utcnow)


class ConnectAuthCodeModel(Base):
    """/connect 授权流程的一次性授权码（PKCE）。

    确认按钮点击后生成，绑定 client 与 code_challenge；
    token 交换时校验 code_verifier，用后即删。
    """

    __tablename__ = "connect_auth_codes"

    id = Column(Integer, primary_key=True, autoincrement=True)
    code = Column(String, unique=True, index=True, nullable=False)
    client_id = Column(String, index=True, nullable=False)
    redirect_uri = Column(String, nullable=False)
    state = Column(String, nullable=False)
    code_challenge = Column(String, nullable=False)
    expires_at = Column(Float, nullable=False)  # Unix 时间戳
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
