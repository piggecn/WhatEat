"""JWT 生成/验证、密码哈希、FastAPI 依赖注入。"""
import os
import secrets
from datetime import datetime, timedelta, timezone

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
import bcrypt
import sqlite3

from app.database import DATABASE_PATH, UPLOAD_DIR, get_db

ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7  # 7 天
REMEMBER_TOKEN_EXPIRE_MINUTES = 60 * 24 * 30  # 记住我：30 天

# SECRET_KEY 持久化到数据目录，保证重启后 token 仍有效。
_KEY_FILE = os.path.join(os.path.dirname(DATABASE_PATH), ".secret_key")


def _load_or_create_secret() -> str:
    key = os.getenv("SECRET_KEY")
    if key:
        return key
    os.makedirs(os.path.dirname(_KEY_FILE), exist_ok=True)
    if os.path.exists(_KEY_FILE):
        with open(_KEY_FILE, "r", encoding="utf-8") as f:
            return f.read().strip()
    key = secrets.token_urlsafe(48)
    with open(_KEY_FILE, "w", encoding="utf-8") as f:
        f.write(key)
    return key


SECRET_KEY = _load_or_create_secret()

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login", auto_error=False)


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(plain: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(plain.encode("utf-8"), hashed.encode("utf-8"))
    except ValueError:
        return False


def create_access_token(user_id: int, username: str, is_admin: bool, remember: bool = False) -> str:
    minutes = REMEMBER_TOKEN_EXPIRE_MINUTES if remember else ACCESS_TOKEN_EXPIRE_MINUTES
    expire = datetime.now(timezone.utc) + timedelta(minutes=minutes)
    payload = {
        "sub": str(user_id),
        "username": username,
        "is_admin": is_admin,
        "exp": expire,
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def decode_token(token: str) -> dict:
    return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])


def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: sqlite3.Connection = Depends(get_db),
) -> sqlite3.Row:
    creds_exc = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="未登录或登录已过期",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if not token:
        raise creds_exc
    try:
        payload = decode_token(token)
    except JWTError:
        raise creds_exc
    user_id = payload.get("sub")
    if user_id is None:
        raise creds_exc
    cur = db.execute("SELECT * FROM users WHERE id = ?", (int(user_id),))
    user = cur.fetchone()
    if user is None:
        raise creds_exc
    return user


def get_admin_user(user: sqlite3.Row = Depends(get_current_user)) -> sqlite3.Row:
    if not user["is_admin"]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="需要管理员权限")
    return user
