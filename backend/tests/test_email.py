from unittest.mock import ANY, patch

import pytest

from app.services.email_service import EmailConfigurationError, SMTPSettings, send_email


def test_get_email_config_does_not_expose_password(client, admin_headers):
    response = client.get("/admin/email/config", headers=admin_headers)

    assert response.status_code == 200
    assert "password" not in response.json()
    assert "password_configured" in response.json()


def test_send_email_endpoint(client, admin_headers):
    with patch("app.routers.admin.send_email") as mocked_send:
        response = client.post(
            "/admin/email/send",
            headers=admin_headers,
            json={
                "recipients": ["user@example.com", "another@example.com"],
                "subject": "测试邮件",
                "text_body": "测试正文",
            },
        )

    assert response.status_code == 200
    assert response.json() == {"message": "邮件发送成功", "recipient_count": 2}
    mocked_send.assert_called_once_with(
        ["user@example.com", "another@example.com"],
        "测试邮件",
        "测试正文",
        None,
        db=ANY,
    )


def test_send_email_requires_smtp_configuration():
    settings = SMTPSettings(
        host="",
        port=587,
        username="",
        password="",
        from_email="",
        from_name="Mobile Portainer",
        use_ssl=False,
        use_starttls=True,
        timeout=10,
    )
    with patch("app.services.email_service.get_smtp_settings", return_value=settings):
        with pytest.raises(EmailConfigurationError):
            send_email(["user@example.com"], "主题", "正文")


def test_send_email_uses_starttls_and_login():
    settings = SMTPSettings(
        host="smtp.example.com",
        port=587,
        username="mailer",
        password="secret",
        from_email="mailer@example.com",
        from_name="系统通知",
        use_ssl=False,
        use_starttls=True,
        timeout=10,
    )
    with patch("app.services.email_service.get_smtp_settings", return_value=settings):
        with patch("app.services.email_service.smtplib.SMTP") as smtp:
            server = smtp.return_value.__enter__.return_value
            send_email(["user@example.com"], "主题", "正文", "<p>正文</p>")

    smtp.assert_called_once_with("smtp.example.com", 587, timeout=10)
    server.starttls.assert_called_once()
    server.login.assert_called_once_with("mailer", "secret")
    assert server.send_message.call_args.kwargs["to_addrs"] == ["user@example.com"]
