"""认证路由 /api/auth/*。"""
import sqlite3

from fastapi import APIRouter, Depends, HTTPException, status

from app import models
from app.auth import create_access_token, get_current_user, verify_password
from app.config import absolute_url
from app.database import get_db

router = APIRouter(prefix="/api/auth", tags=["auth"])


def _enrich_user(u: dict) -> dict:
    """给 user dict 附加 avatar_url（仅上传路径存在时）。"""
    ap = u.get("avatar_path")
    if ap:
        u["avatar_url"] = absolute_url(ap)
    return u


@router.post("/login", response_model=models.LoginResponse)
def login(body: models.LoginRequest, db: sqlite3.Connection = Depends(get_db)):
    cur = db.execute("SELECT * FROM users WHERE username = ?", (body.username,))
    user = cur.fetchone()
    if not user or not verify_password(body.password, user["password_hash"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="用户名或密码错误",
        )
    token = create_access_token(
        user["id"], user["username"], bool(user["is_admin"]), remember=body.remember_me
    )
    return {
        "token": token,
        "user": _enrich_user({
            "id": user["id"],
            "username": user["username"],
            "display_name": user["display_name"] if "display_name" in user.keys() else None,
            "is_admin": bool(user["is_admin"]),
            "avatar": user["avatar"] if "avatar" in user.keys() else None,
            "avatar_path": user["avatar_path"] if "avatar_path" in user.keys() else None,
        }),
    }


@router.get("/me", response_model=models.UserOut)
def me(user: sqlite3.Row = Depends(get_current_user)):
    return _enrich_user({
        "id": user["id"],
        "username": user["username"],
        "display_name": user["display_name"] if "display_name" in user.keys() else None,
        "is_admin": bool(user["is_admin"]),
        "avatar": user["avatar"] if "avatar" in user.keys() else None,
        "avatar_path": user["avatar_path"] if "avatar_path" in user.keys() else None,
    })
