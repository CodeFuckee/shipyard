"""可逆加密工具 —— 用于安全持久化 SMTP 密码等敏感配置。

使用 AES-GCM 风格的加密（通过 hashlib + XOR + HMAC 标签），
密钥从 SECRET_KEY 环境变量派生。
"""

import base64
import hashlib
import hmac
import os
import secrets

# 密钥派生参数
_KEY_ITERATIONS = 200_000
_KEY_LENGTH = 32  # 256-bit

# 固定的 salt（用于派生加密密钥，不用于每条记录）
_KEY_SALT = b"mobile_portainer_smtp_encryption_salt_v1"


def _derive_encryption_key() -> bytes:
    """从环境变量或预置种子派生 256-bit 加密密钥。"""
    secret = os.getenv("SECRET_KEY", "mobile_portainer_default_secret_v1").encode(
        "utf-8"
    )
    return hashlib.pbkdf2_hmac(
        "sha256", secret, _KEY_SALT, _KEY_ITERATIONS, dklen=_KEY_LENGTH
    )


def encrypt(plaintext: str) -> str:
    """加密纯文本字符串，返回 base64 编码的密文。

    格式: <nonce:12> + <ciphertext> + <hmac_tag:32>
    全部编码为一个 base64 字符串。
    """
    if not plaintext:
        return ""

    key = _derive_encryption_key()
    nonce = secrets.token_bytes(12)
    plaintext_bytes = plaintext.encode("utf-8")

    # 使用 HMAC 生成密钥流，与 nonce 绑定
    stream_key = hmac.new(key, nonce + b"stream", hashlib.sha256).digest()

    # XOR 加密（若明文长于 32 字节，使用 keystream 扩展）
    ciphertext = bytearray()
    keystream = stream_key
    while len(keystream) < len(plaintext_bytes):
        keystream += hmac.new(key, keystream[-32:] + nonce, hashlib.sha256).digest()
    for i, b in enumerate(plaintext_bytes):
        ciphertext.append(b ^ keystream[i])

    # 计算 MAC 标签: HMAC(nonce + ciphertext)
    tag = hmac.new(key, nonce + bytes(ciphertext) + b"auth", hashlib.sha256).digest()

    # 组合: nonce + ciphertext + tag
    payload = nonce + bytes(ciphertext) + tag
    return base64.urlsafe_b64encode(payload).decode("ascii")


def decrypt(encoded: str) -> str:
    """解密由 encrypt() 生成的密文，返回原始纯文本。"""
    if not encoded:
        return ""

    key = _derive_encryption_key()
    try:
        payload = base64.urlsafe_b64decode(encoded.encode("ascii"))
    except (ValueError, TypeError):
        raise ValueError("密文格式无效：无法解码 base64")

    if len(payload) < 12 + 1 + 32:
        raise ValueError("密文长度不足")

    nonce = payload[:12]
    tag = payload[-32:]
    ciphertext = payload[12:-32]

    # 验证 MAC 标签
    expected_tag = hmac.new(key, nonce + ciphertext + b"auth", hashlib.sha256).digest()
    if not hmac.compare_digest(tag, expected_tag):
        raise ValueError("密文校验失败：密码可能被篡改，或 SECRET_KEY 已变更")

    # 解密
    stream_key = hmac.new(key, nonce + b"stream", hashlib.sha256).digest()
    plaintext = bytearray()
    keystream = stream_key
    while len(keystream) < len(ciphertext):
        keystream += hmac.new(key, keystream[-32:] + nonce, hashlib.sha256).digest()
    for i, b in enumerate(ciphertext):
        plaintext.append(b ^ keystream[i])

    return bytes(plaintext).decode("utf-8")
