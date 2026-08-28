"""个人资料路由 /api/users/profile。"""
import sqlite3

from fastapi import APIRouter, Depends, HTTPException

from app import models
from app.auth import get_current_user
from app.config import absolute_url
from app.database import get_db

router = APIRouter(prefix="/api/users", tags=["profile"])

VALID_CAROUSEL_TYPES = {"most_cooked", "favorites", "recent", "random"}


def _enrich_user(u: dict) -> dict:
    ap = u.get("avatar_path")
    if ap:
        u["avatar_url"] = absolute_url(ap)
    return u


@router.get("/profile", response_model=models.ProfileSettingsOut)
def get_profile(
    user=Depends(get_current_user),
):
    return _enrich_user({
        "id": user["id"],
        "username": user["username"],
        "display_name": user["display_name"],
        "avatar": user["avatar"],
        "avatar_path": user["avatar_path"] if "avatar_path" in user.keys() else None,
        "is_admin": bool(user["is_admin"]),
        "carousel_type": user["carousel_type"] or "most_cooked",
        "carousel_limit": user["carousel_limit"] or 10,
    })


@router.put("/profile", response_model=models.ProfileSettingsOut)
def update_profile(
    body: models.ProfileUpdateIn,
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    updates = []
    params = []

    updates.append("display_name = ?")
    params.append(body.display_name)

    # 管理员可修改账户名
    if body.username is not None and body.username != user["username"]:
        if not user["is_admin"]:
            raise HTTPException(status_code=403, detail="只有管理员可以修改账户名")
        existing = db.execute("SELECT id FROM users WHERE username = ? AND id != ?", (body.username, user["id"])).fetchone()
        if existing:
            raise HTTPException(status_code=400, detail="该账户名已被使用")
        updates.append("username = ?")
        params.append(body.username)

    updates.append("avatar = ?")
    params.append(body.avatar)

    if body.carousel_type is not None:
        if body.carousel_type not in VALID_CAROUSEL_TYPES:
            raise HTTPException(
                status_code=400,
                detail=f"无效 carousel_type，可选: {', '.join(sorted(VALID_CAROUSEL_TYPES))}",
            )
        updates.append("carousel_type = ?")
        params.append(body.carousel_type)

    if body.carousel_limit is not None:
        if not (5 <= body.carousel_limit <= 20):
            raise HTTPException(status_code=400, detail="carousel_limit 必须在 5-20 之间")
        updates.append("carousel_limit = ?")
        params.append(body.carousel_limit)

    params.append(user["id"])
    set_sql = ", ".join(updates)
    db.execute(f"UPDATE users SET {set_sql} WHERE id = ?", params)
    db.commit()

    r = db.execute("SELECT * FROM users WHERE id = ?", (user["id"],)).fetchone()
    return _enrich_user({
        "id": r["id"],
        "username": r["username"],
        "display_name": r["display_name"],
        "avatar": r["avatar"],
        "avatar_path": r["avatar_path"] if "avatar_path" in r.keys() else None,
        "is_admin": bool(r["is_admin"]),
        "carousel_type": r["carousel_type"] or "most_cooked",
        "carousel_limit": r["carousel_limit"] or 10,
    })
