"""SMTP 邮件发送服务。"""

from dataclasses import dataclass
from email.message import EmailMessage
from email.utils import formataddr
import smtplib
import ssl
from typing import List, Optional

from sqlalchemy.orm import Session

from app.core import config
from app.core.crypto import encrypt, decrypt
from app.db.models import SMTPSettingsModel


class EmailConfigurationError(ValueError):
    """SMTP 配置不完整或无效。"""


class EmailDeliveryError(RuntimeError):
    """SMTP 服务器未能投递邮件。"""


@dataclass(frozen=True)
class SMTPSettings:
    host: str
    port: int
    username: str
    password: str
    from_email: str
    from_name: str
    use_ssl: bool
    use_starttls: bool
    timeout: int


def _get_db_smtp_settings(db: Session) -> Optional[SMTPSettingsModel]:
    """从数据库读取 SMTP 配置记录（id=1），不存在则返回 None。"""
    return db.get(SMTPSettingsModel, 1)


def get_smtp_settings(db: Optional[Session] = None) -> SMTPSettings:
    """读取 SMTP 配置，优先使用数据库持久化配置，回退到环境变量。"""
    db_settings: Optional[SMTPSettingsModel] = None
    db_password = ""

    if db is not None:
        db_settings = _get_db_smtp_settings(db)
        if db_settings and db_settings.encrypted_password:
            try:
                db_password = decrypt(db_settings.encrypted_password)
            except ValueError:
                db_password = ""

    # 数据库配置优先，环境变量作为回退值
    host = db_settings.host if db_settings and db_settings.host else config.SMTP_HOST
    port = (
        db_settings.port
        if db_settings and db_settings.port is not None
        else config.SMTP_PORT
    )
    username = (
        db_settings.username
        if db_settings and db_settings.username
        else config.SMTP_USERNAME
    )
    password = db_password if db_password else config.SMTP_PASSWORD
    from_email = (
        db_settings.from_email
        if db_settings and db_settings.from_email
        else config.SMTP_FROM_EMAIL
    )
    from_name = (
        db_settings.from_name
        if db_settings and db_settings.from_name
        else config.SMTP_FROM_NAME
    )
    use_ssl = (
        bool(db_settings.use_ssl)
        if db_settings and db_settings.use_ssl is not None
        else config.SMTP_USE_SSL
    )
    use_starttls = (
        bool(db_settings.use_starttls)
        if db_settings and db_settings.use_starttls is not None
        else config.SMTP_USE_STARTTLS
    )
    timeout = (
        db_settings.timeout
        if db_settings and db_settings.timeout is not None
        else config.SMTP_TIMEOUT
    )

    return SMTPSettings(
        host=host,
        port=port,
        username=username,
        password=password,
        from_email=from_email,
        from_name=from_name,
        use_ssl=use_ssl,
        use_starttls=use_starttls,
        timeout=timeout,
    )


def get_smtp_config_status(db: Optional[Session] = None) -> dict:
    """返回可供管理端展示的非敏感 SMTP 配置。"""
    settings = get_smtp_settings(db)
    return {
        "configured": bool(settings.host and settings.from_email),
        "host": settings.host,
        "port": settings.port,
        "username": settings.username,
        "from_email": settings.from_email,
        "from_name": settings.from_name,
        "use_ssl": settings.use_ssl,
        "use_starttls": settings.use_starttls and not settings.use_ssl,
        "timeout": settings.timeout,
        "password_configured": bool(settings.password),
        "source": "database"
        if (db is not None and _get_db_smtp_settings(db))
        else "env",
    }


def save_smtp_settings(db: Session, settings_data: dict) -> SMTPSettingsModel:
    """持久化保存 SMTP 配置到数据库（id=1）。密码会加密存储。"""
    db_settings = _get_db_smtp_settings(db)
    if db_settings is None:
        db_settings = SMTPSettingsModel(id=1)
        db.add(db_settings)

    # 更新字段
    for field in ("host", "port", "username", "from_email", "from_name", "timeout"):
        if field in settings_data:
            setattr(db_settings, field, settings_data[field])
    for bool_field in ("use_ssl", "use_starttls"):
        if bool_field in settings_data:
            setattr(db_settings, bool_field, 1 if settings_data[bool_field] else 0)
    if "password" in settings_data and settings_data["password"]:
        db_settings.encrypted_password = encrypt(settings_data["password"])

    db.commit()
    db.refresh(db_settings)
    return db_settings


def send_email(
    recipients: List[str],
    subject: str,
    text_body: str,
    html_body: Optional[str] = None,
    db: Optional[Session] = None,
) -> None:
    """通过已配置的 SMTP 服务器发送一封邮件。"""
    settings = get_smtp_settings(db)
    if not settings.host or not settings.from_email:
        raise EmailConfigurationError("SMTP_HOST 和 SMTP_FROM_EMAIL 必须配置")
    if not 1 <= settings.port <= 65535:
        raise EmailConfigurationError("SMTP_PORT 必须介于 1 到 65535 之间")
    if settings.timeout <= 0:
        raise EmailConfigurationError("SMTP_TIMEOUT 必须大于 0")
    if settings.use_ssl and settings.use_starttls:
        raise EmailConfigurationError("SMTP_USE_SSL 与 SMTP_USE_STARTTLS 不能同时启用")
    if settings.username and not settings.password:
        raise EmailConfigurationError("配置 SMTP_USERNAME 时必须同时配置 SMTP_PASSWORD")

    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = formataddr((settings.from_name, settings.from_email))
    message["To"] = ", ".join(recipients)
    message.set_content(text_body)
    if html_body:
        message.add_alternative(html_body, subtype="html")

    try:
        smtp_class = smtplib.SMTP_SSL if settings.use_ssl else smtplib.SMTP
        with smtp_class(
            settings.host, settings.port, timeout=settings.timeout
        ) as server:
            if settings.use_starttls:
                server.starttls(context=ssl.create_default_context())
            if settings.username:
                server.login(settings.username, settings.password)
            server.send_message(
                message, from_addr=settings.from_email, to_addrs=recipients
            )
    except (OSError, smtplib.SMTPException) as exc:
        raise EmailDeliveryError("SMTP 邮件发送失败") from exc
