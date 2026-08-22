import uuid
from datetime import datetime

from sqlalchemy import Column, DateTime, Float, Index, Integer, String, Text

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


class OIDCIdentityModel(Base):
    """OIDC subject 与 Shipyard API Key 的稳定映射。"""

    __tablename__ = "oidc_identities"
    __table_args__ = (
        Index(
            "uq_oidc_identities_issuer_subject", "issuer", "subject", unique=True
        ),
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    # SQLite 的 create_all 无法为旧表追加复合唯一约束；启动迁移会补建
    # 同名唯一索引，保证新旧部署均可安全处理并发首次登录。
    issuer = Column(String, nullable=False, index=True)
    subject = Column(String, nullable=False, index=True)
    api_key_id = Column(String, nullable=False, unique=True)
    created_at = Column(DateTime, default=datetime.utcnow)
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


class AgentChatHistoryModel(Base):
    """AI 助手对话历史 — 固定使用 id=1 的单条记录（issue #32）。

    保存用户与 AI 助手的完整对话消息列表（role/content/steps 的 JSON
    数组），每次成功对话后覆盖保存，供前端聊天窗口重新打开时恢复
    历史对话；与调试日志表 agent_chat_logs（仅保留 100 条）不同，
    本表为单例会话长期保留，DELETE 端点支持一键清空。
    """

    __tablename__ = "agent_chat_history"

    id = Column(Integer, primary_key=True, default=1)
    messages_json = Column(Text, nullable=True)  # 完整对话消息列表 JSON
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)



class AgentChatSessionModel(Base):
    """AI 助手对话会话 — 多会话历史列表（issue #38）。

    每个成功对话（流式与非流式）保存/更新为一条会话；「打开新会话」
    前的当前对话快照也保存为一条会话。标题自动取首条用户消息摘要
    （前 30 字符）；会话列表最多保留 MAX_SESSIONS（100）条，超出
    自动删除最旧会话（与调试日志表 agent_chat_logs 的清理策略一致）。

    与 agent_chat_history（单例覆盖式，issue #32）不同：本表为多行
    记录，供聊天窗口头部「历史」按钮浏览并重新打开任意一条过往对话；
    旧单例记录在首次访问会话列表时自动迁移为一条会话（见
    app/agent/chat_history.py 的 _migrate_singleton）。
    """

    __tablename__ = "agent_chat_sessions"

    id = Column(Integer, primary_key=True, autoincrement=True)
    title = Column(String(200), nullable=False, default="新会话")  # 首条用户消息摘要
    messages_json = Column(Text, nullable=True)  # 完整对话消息列表 JSON
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


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
