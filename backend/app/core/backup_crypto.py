"""备份文件流式加密 —— 复用 crypto.py 的 XOR+HMAC 模式扩展为文件级加密。

与 crypto.py（字符串加密）同源：
- 密钥从 SECRET_KEY 环境变量派生（PBKDF2-SHA256，独立 salt，用途分离）
- XOR 密钥流 + HMAC 完整性标签

文件格式（密文）:
    MAGIC(8B) | version(1B) | nonce(12B) | ciphertext_stream | hmac_tag(32B)

- 流式分块处理（默认 64KB），不整读文件进内存，支持任意大小备份
- HMAC 标签覆盖 magic+version+nonce+全部密文，防篡改
- 解密失败时输出文件会被删除，不会留下半截明文
"""

import hashlib
import hmac
import os
import secrets
from pathlib import Path
from typing import Optional, Union

# 魔数头：标识备份文件格式（8 字节）
MAGIC_HEADER = b"SHPYBK01"
_FORMAT_VERSION = b"\x01"

# 密钥派生参数（与 crypto.py 一致）
_KEY_ITERATIONS = 200_000
_KEY_LENGTH = 32  # 256-bit
_KEY_SALT = b"mobile_portainer_backup_encryption_salt_v1"

# 加密分块大小（64KB）
_CHUNK_SIZE = 64 * 1024
# HMAC-SHA256 标签长度
_TAG_LENGTH = 32

_PATH = Union[str, Path]


def _derive_key(secret: bytes) -> bytes:
    """从 SECRET_KEY 派生 256-bit 加密密钥（独立 salt，与 SMTP 加密用途分离）。"""
    return hashlib.pbkdf2_hmac(
        "sha256", secret, _KEY_SALT, _KEY_ITERATIONS, dklen=_KEY_LENGTH
    )


def _get_key(key: Optional[bytes] = None) -> bytes:
    """解析加密密钥：显式传入优先，否则从 SECRET_KEY 环境变量派生。"""
    if key is not None:
        return key
    secret = os.getenv("SECRET_KEY", "mobile_portainer_default_secret_v1").encode(
        "utf-8"
    )
    return _derive_key(secret)


def _keystream(key: bytes, nonce: bytes):
    """XOR 密钥流生成器（与 crypto.py 相同的扩展方式，可无限续块）。

    block1 = HMAC(key, nonce + "stream")
    blockN = HMAC(key, block(N-1) + nonce)
    """
    prev = nonce + b"stream"
    while True:
        block = hmac.new(key, prev, hashlib.sha256).digest()
        prev = block + nonce
        yield block


def encrypt_file(
    src: _PATH, dst: _PATH, key: Optional[bytes] = None
) -> Path:
    """流式加密 src 文件到 dst。

    返回 dst 路径。加密过程：
    1. 写头（magic + version + nonce）
    2. 分块 XOR 密钥流写密文，同时累计 HMAC
    3. 追加整体 HMAC 标签
    """
    src, dst = Path(src), Path(dst)
    key = _get_key(key)
    nonce = secrets.token_bytes(12)

    dst.parent.mkdir(parents=True, exist_ok=True)
    header = MAGIC_HEADER + _FORMAT_VERSION + nonce
    hasher = hmac.new(key, header + b"auth", hashlib.sha256)

    with open(src, "rb") as fin, open(dst, "wb") as fout:
        fout.write(header)
        stream = _keystream(key, nonce)
        while True:
            chunk = fin.read(_CHUNK_SIZE)
            if not chunk:
                break
            # 用密钥流逐字节 XOR 明文生成密文
            cipher = bytearray(chunk)
            offset = 0
            while offset < len(cipher):
                block = next(stream)
                for i, ks in enumerate(block[: len(cipher) - offset]):
                    cipher[offset + i] ^= ks
                offset += min(len(block), len(cipher) - offset)
            hasher.update(cipher)
            fout.write(bytes(cipher))
        fout.write(hasher.digest())
    return dst


def decrypt_file(
    src: _PATH, dst: _PATH, key: Optional[bytes] = None
) -> Path:
    """解密 src（encrypt_file 产物）到 dst。

    校验顺序：魔数 → 最小长度 → HMAC 标签。任一失败抛出异常，
    并删除可能已写出的输出文件，避免留下不完整的明文。
    """
    src, dst = Path(src), Path(dst)
    key = _get_key(key)

    if not src.exists():
        raise FileNotFoundError(f"加密文件不存在: {src}")

    with open(src, "rb") as fin:
        header = fin.read(len(MAGIC_HEADER) + 1 + 12)
        if len(header) < len(MAGIC_HEADER) + 1 + 12:
            raise ValueError("备份文件格式无效：文件过短")
        if header[:8] != MAGIC_HEADER:
            raise ValueError("备份文件格式无效：魔数不匹配（可能不是加密备份）")
        if header[8:9] != _FORMAT_VERSION:
            raise ValueError(f"备份文件格式版本不支持: {header[8:9]!r}")

        nonce = header[9:]
        # 剩余内容 = 密文流 + 末尾 32 字节 HMAC 标签
        fin.seek(0, os.SEEK_END)
        total = fin.tell()
        # 空文件也是合法备份（密文长度为 0），但至少要有头 + 标签
        if total < len(header) + _TAG_LENGTH:
            raise ValueError("备份文件格式无效：密文内容为空")

        fin.seek(len(header))
        cipher_len = total - len(header) - _TAG_LENGTH
        hasher = hmac.new(key, header + b"auth", hashlib.sha256)
        stream = _keystream(key, nonce)

        dst.parent.mkdir(parents=True, exist_ok=True)
        try:
            with open(dst, "wb") as fout:
                remaining = cipher_len
                while remaining > 0:
                    size = min(_CHUNK_SIZE, remaining)
                    cipher = fin.read(size)
                    if not cipher:
                        raise ValueError("备份文件格式无效：密文不完整")
                    hasher.update(cipher)
                    plain = bytearray()
                    while len(plain) < len(cipher):
                        block = next(stream)
                        plain.extend(block[: len(cipher) - len(plain)])
                    for i, b in enumerate(cipher):
                        plain[i] = b ^ plain[i]
                    fout.write(bytes(plain))
                    remaining -= size

                expected_tag = hasher.digest()
                actual_tag = fin.read(_TAG_LENGTH)
                if len(actual_tag) != _TAG_LENGTH or not hmac.compare_digest(
                    expected_tag, actual_tag
                ):
                    raise ValueError(
                        "备份文件校验失败：文件可能被篡改，或 SECRET_KEY 已变更"
                    )
        except Exception:
            # 校验失败或 IO 错误时清理输出，不留半截明文
            dst.unlink(missing_ok=True)
            raise
    return dst
