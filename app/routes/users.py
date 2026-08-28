import os
import sqlite3

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel

from app.auth import get_current_user, hash_password, verify_password
from app.config import absolute_url
from app.database import get_db
from app.models import UserCreate, UserProfileUpdate, PasswordChange

router = APIRouter(prefix="/api/users", tags=["users"])

AVATAR_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "avatars")
os.makedirs(AVATAR_DIR, exist_ok=True)

# 预设 key -> (旧路径兼容值, emoji, display_name)
AVATAR_PRESETS = [
    ("dad",      "presets/avatar_dad.png",           "👨", "爸爸"),
    ("mom",      "presets/avatar_mom.png",           "👩", "妈妈"),
    ("grandpa",  "presets/avatar_grandpa.png",       "👴", "爷爷"),
    ("grandma",  "presets/avatar_grandma.png",       "👵", "奶奶"),
    ("brother",  "presets/avatar_brother.png",       "🧑", "哥哥"),
    ("sister",   "presets/avatar_sister.png",        "👧", "姐姐"),
    ("little_brother", "presets/avatar_littlebrother.png", "👦", "弟弟"),
    ("little_sister",  "presets/avatar_littlesister.png",  "🧒", "妹妹"),
    ("son",      "presets/avatar_son.png",           "👶", "儿子"),
    ("daughter", "presets/avatar_daughter.png",      "👧", "女儿"),
]


def _enrich_user(u: dict) -> dict:
    ap = u.get("avatar_path")
    if ap:
        u["avatar_url"] = absolute_url(ap)
    return u


# ---- 列表 ----
@router.get("/list")
def list_users(
    current_user: dict = Depends(get_current_user),
    conn: sqlite3.Connection = Depends(get_db),
):
    if not current_user["is_admin"]:
        raise HTTPException(status_code=403, detail="无权限")
    rows = conn.execute(
        "SELECT id, username, display_name, avatar, avatar_path, is_admin, created_at FROM users ORDER BY id"
    ).fetchall()
    return [_enrich_user(dict(r)) for r in rows]


# ---- 创建用户（前端 POST /api/users） ----
@router.post("")
def create_user(
    request: UserCreate,
    current_user: dict = Depends(get_current_user),
    conn: sqlite3.Connection = Depends(get_db),
):
    if not current_user["is_admin"]:
        raise HTTPException(status_code=403, detail="只有管理员可以创建用户")
    existing = conn.execute("SELECT id FROM users WHERE username = ?", (request.username,)).fetchone()
    if existing:
        raise HTTPException(status_code=400, detail="该账户名已被使用")
    if not request.display_name:
        raise HTTPException(status_code=400, detail="请选择家庭成员称谓")

    # 按 display_name 匹配预设（也兼容 avatar 是预设 key）
    avatar_key = request.avatar or "dad"
    avatar_emoji = "👨"
    display_name = request.display_name
    for key, _old_path, emoji, name in AVATAR_PRESETS:
        if request.avatar == key or request.display_name == name:
            avatar_key = key
            avatar_emoji = emoji
            if request.display_name == name:
                display_name = name
            break

    # 使用 bcrypt 统一哈希
    hashed = hash_password(request.password)

    conn.execute(
        """INSERT INTO users (username, password_hash, display_name, avatar, is_admin, created_at)
           VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)""",
        (request.username, hashed, display_name, avatar_key, int(request.is_admin or 0)),
    )
    user_id = conn.execute("SELECT last_insert_rowid()").fetchone()[0]
    conn.commit()
    return {
        "id": user_id,
        "username": request.username,
        "display_name": display_name,
        "avatar": avatar_key,
        "avatar_emoji": avatar_emoji,
    }


# ---- 删除用户 ----
@router.delete("/{user_id}")
def delete_user(
    user_id: int,
    current_user: dict = Depends(get_current_user),
    conn: sqlite3.Connection = Depends(get_db),
):
    if not current_user["is_admin"]:
        raise HTTPException(status_code=403, detail="只有管理员可以删除用户")
    if user_id == current_user["id"]:
        raise HTTPException(status_code=400, detail="不能删除自己")
    target = conn.execute("SELECT id, is_admin FROM users WHERE id = ?", (user_id,)).fetchone()
    if not target:
        raise HTTPException(status_code=404, detail="用户不存在")
    if target["is_admin"]:
        raise HTTPException(status_code=400, detail="不能删除管理员账户")
    conn.execute("DELETE FROM users WHERE id = ?", (user_id,))
    conn.commit()
    return {"ok": True}


# ---- 本人资料 ----
@router.get("/get_me")
def get_me(current_user: dict = Depends(get_current_user)):
    return _enrich_user({
        "id": current_user["id"],
        "username": current_user["username"],
        "display_name": current_user.get("display_name") or current_user["username"],
        "avatar": current_user.get("avatar"),
        "avatar_path": current_user.get("avatar_path"),
        "is_admin": current_user["is_admin"],
    })


@router.put("/update_me")
def update_me(
    request: UserProfileUpdate,
    current_user: dict = Depends(get_current_user),
    conn: sqlite3.Connection = Depends(get_db),
):
    conn.execute(
        "UPDATE users SET display_name = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
        (request.display_name, current_user["id"]),
    )
    conn.commit()
    return {"ok": True}


# ---- 修改本人密码：PUT /api/users/me/password（前端调用路径） ----
@router.put("/me/password")
def update_own_password(
    body: PasswordChange,
    current_user: dict = Depends(get_current_user),
    conn: sqlite3.Connection = Depends(get_db),
):
    """使用 bcrypt 校验原密码，再用 bcrypt 存新密码。"""
    row = conn.execute("SELECT password_hash FROM users WHERE id = ?", (current_user["id"],)).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="用户不存在")
    if not verify_password(body.old_password, row["password_hash"]):
        raise HTTPException(status_code=400, detail="当前密码不正确")
    new_hashed = hash_password(body.new_password)
    conn.execute("UPDATE users SET password_hash = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                 (new_hashed, current_user["id"]))
    conn.commit()
    return {"ok": True}


# ---- 头像上传（路径保留兼容） ----
@router.post("/avatar/upload")
async def upload_avatar(
    image: UploadFile = File(...),
    avatar: str = None,
    current_user: dict = Depends(get_current_user),
    conn: sqlite3.Connection = Depends(get_db),
):
    import hashlib

    if image and not image.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="请上传有效的图片文件")

    user_id = current_user["id"]
    avatar_path = None

    if image:
        ext = os.path.splitext(image.filename)[1].lower() if image.filename else ".png"
        if ext not in (".jpg", ".jpeg", ".png", ".webp"):
            ext = ".png"
        avatar_name = f"user_{user_id}_avatar{ext}"
        avatar_path = os.path.join(AVATAR_DIR, avatar_name)
        with open(avatar_path, "wb") as f:
            f.write(await image.read())

    new_avatar = avatar or current_user.get("avatar") or "dad"
    new_avatar_path = avatar_path if image else None

    conn.execute(
        """UPDATE users SET avatar = ?, avatar_path = ?, updated_at = CURRENT_TIMESTAMP
           WHERE id = ?""",
        (new_avatar, new_avatar_path, user_id),
    )
    conn.commit()

    return {
        "avatar": new_avatar,
        "avatar_path": new_avatar_path,
    }
