"""Web 页面路由，渲染 Jinja2 模板。"""
import os
import sqlite3
from typing import Optional

from fastapi import APIRouter, Depends, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

from app.auth import decode_token
from app.database import DATABASE_PATH

router = APIRouter(tags=["pages"])

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
templates = Jinja2Templates(directory=os.path.join(BASE_DIR, "templates"))

# 头像渲染辅助函数：presets 路径 → emoji SVG，文件路径 → 可访问 URL
AVATAR_EMOJI_MAP = {
    "爸爸": "👨", "妈妈": "👩", "爷爷": "👴", "奶奶": "👵",
    "哥哥": "🧑", "姐姐": "👧", "弟弟": "👦", "妹妹": "🧒",
}


def _avatar_svg(emoji: str, size: int = 32) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}"'
        f' viewBox="0 0 {size} {size}" fill="none">'
        f'<circle cx="{size//2}" cy="{size//2}" r="{size-2}" fill="#f5e6d3" stroke="#e0d4c1" stroke-width="1.5"/>'
        f'<text x="{size//2}" y="{size//2 + size//8}" text-anchor="middle" font-size="{size//2}">{emoji}</text>'
        f'</svg>'
    )


def avatar_url(avatar: Optional[str], avatar_path: Optional[str],
               display_name: str = "", size: int = 32) -> Optional[str]:
    """返回头像的可用 URL；没有可用头像返回 None。"""
    # 优先级 1：真实上传的文件
    if avatar_path and os.path.isfile(avatar_path):
        basename = os.path.basename(avatar_path)
        return f"/avatars/{basename}"
    # 优先级 2：display_name 匹配预设 → 返回 inline SVG
    if display_name:
        emoji = AVATAR_EMOJI_MAP.get(display_name, "👤")
        svg = _avatar_svg(emoji, size)
        return f"data:image/svg+xml,{svg}"
    return None


def page_user(request: Request) -> Optional[dict]:
    token = request.cookies.get("recipe_token", "")
    if not token:
        auth = request.headers.get("authorization", "")
        if auth.lower().startswith("bearer "):
            token = auth[7:]
    if not token:
        return None
    try:
        payload = decode_token(token)
        uid = int(payload.get("sub", 0))
    except Exception:
        return None
    conn = _conn()
    try:
        row = conn.execute(
            "SELECT id, username, display_name, avatar, is_admin, avatar_path FROM users WHERE id = ?", (uid,)
        ).fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def _conn() -> sqlite3.Connection:
    conn = sqlite3.connect(DATABASE_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


CATEGORIES = ["早餐", "午餐", "晚餐", "甜点", "小吃", "饮品"]


SORT_OPTIONS = [
    ("added_desc",  "最近收藏"),
    ("added_asc",   "最早收藏"),
    ("alpha",       "菜名 A→Z"),
    ("cook_time",   "烹饪时间短→长"),
    ("created_desc","创建时间新→旧"),
]
_INDEX_SORT_OPTIONS = [
    ("created_desc","创建时间新→旧"),
    ("cook_time",   "烹饪时间短→长"),
    ("alpha",       "菜名 A→Z"),
]


def _sort_sql(sort: str, default: str = "r.created_at DESC"):
    return {
        "alpha":        "r.title COLLATE NOCASE ASC",
        "cook_time":    "COALESCE(r.cook_time, 0) + COALESCE(r.prep_time, 0) ASC, r.created_at DESC",
        "created_desc": "r.created_at DESC",
        "created_asc":  "r.created_at ASC",
        "added_desc":   "fav.created_at DESC, r.created_at DESC",
        "added_asc":    "fav.created_at ASC, r.created_at DESC",
    }.get(sort, default)


def _list_recipes(conn, user_id: int, category=None, q=None, sort: str = "created_desc") -> list:
    where, params = [], []
    if category:
        where.append("r.category = ?")
        params.append(category)
    if q:
        where.append("(r.title LIKE ? OR r.description LIKE ?)")
        params.extend([f"%{q}%", f"%{q}%"])
    where_sql = (" WHERE " + " AND ".join(where)) if where else ""
    order_sql = _sort_sql(sort, "r.created_at DESC")
    rows = conn.execute(
        f"""
        SELECT r.id, r.title, r.description, r.category, r.image_path,
               r.prep_time, r.cook_time, r.created_at,
               u.username AS author, u.display_name AS author_display_name, u.avatar AS author_avatar,
               EXISTS(SELECT 1 FROM favorites f WHERE f.user_id = ? AND f.recipe_id = r.id) AS is_favorite
        FROM recipes r
        JOIN users u ON u.id = r.created_by
        {where_sql}
        ORDER BY {order_sql}
        """,
        [user_id] + params,
    ).fetchall()
    return [dict(r) for r in rows]


def _list_favorites(conn, user_id: int, category=None, q=None, sort: str = "added_desc") -> list:
    where, params = ["fav.user_id = ?"], [user_id]
    if category:
        where.append("r.category = ?")
        params.append(category)
    if q:
        where.append("(r.title LIKE ? OR r.description LIKE ?)")
        params.extend([f"%{q}%", f"%{q}%"])
    where_sql = " WHERE " + " AND ".join(where)
    order_map = {
        "added_desc":   "fav.id DESC",
        "added_asc":    "fav.id ASC",
        "alpha":        "r.title COLLATE NOCASE ASC",
        "cook_time":    "COALESCE(r.cook_time, 0) + COALESCE(r.prep_time, 0) ASC, r.created_at DESC",
        "created_desc": "r.created_at DESC",
    }
    order_sql = order_map.get(sort, order_map["added_desc"])
    rows = conn.execute(
        f"""
        SELECT r.id, r.title, r.description, r.category, r.image_path,
               r.prep_time, r.cook_time, r.created_at,
               u.username AS author, u.display_name AS author_display_name, u.avatar AS author_avatar,
               1 AS is_favorite
        FROM favorites fav
        JOIN recipes r ON r.id = fav.recipe_id
        JOIN users u ON u.id = r.created_by
        {where_sql}
        ORDER BY {order_sql}
        """,
        params,
    ).fetchall()
    return [dict(r) for r in rows]


def _get_recipe(conn, user_id: int, recipe_id: int) -> Optional[dict]:
    row = conn.execute(
        """
        SELECT r.id, r.title, r.description, r.category, r.servings,
               r.prep_time, r.cook_time, r.image_path, r.created_at, r.updated_at,
               u.username AS author, u.display_name AS author_display_name, u.avatar AS author_avatar,
               EXISTS(SELECT 1 FROM favorites f WHERE f.user_id = ? AND f.recipe_id = r.id) AS is_favorite
        FROM recipes r
        JOIN users u ON u.id = r.created_by
        WHERE r.id = ?
        """,
        (user_id, recipe_id),
    ).fetchone()
    if not row:
        return None
    ingredients = [dict(i) for i in conn.execute(
        "SELECT name, amount, unit FROM ingredients WHERE recipe_id = ? ORDER BY id", (recipe_id,)
    ).fetchall()]
    steps = [dict(s) for s in conn.execute(
        "SELECT step_number, description FROM steps WHERE recipe_id = ? ORDER BY step_number", (recipe_id,)
    ).fetchall()]
    d = dict(row)
    d["is_favorite"] = bool(d["is_favorite"])
    d["ingredients"] = ingredients
    d["steps"] = steps
    return d


def _list_users(conn) -> list:
    rows = conn.execute(
        "SELECT id, username, display_name, avatar, is_admin, avatar_path, created_at FROM users ORDER BY id"
    ).fetchall()
    return [dict(r) for r in rows]


def _list_today_meals(conn, user_id: int) -> list:
    from datetime import date as _date
    today = _date.today().isoformat()
    rows = conn.execute(
        """
        SELECT m.id, m.meal_type, m.recipe_id, r.title, r.image_path
        FROM meals m
        LEFT JOIN recipes r ON r.id = m.recipe_id
        WHERE m.user_id = ? AND m.date = ?
        ORDER BY m.created_at DESC
        """,
        (user_id, today),
    ).fetchall()
    return [dict(r) for r in rows]


@router.get("/", response_class=HTMLResponse)
def index(request: Request, user=Depends(page_user)):
    if not user:
        return RedirectResponse("/login", status_code=303)
    category = request.query_params.get("category") or ""
    q = request.query_params.get("q") or ""
    sort = request.query_params.get("sort") or "created_desc"
    conn = _conn()
    try:
        recipes = _list_recipes(conn, user["id"], category or None, q or None, sort)
        today_meals = _list_today_meals(conn, user["id"])
    finally:
        conn.close()
    return templates.TemplateResponse(request, "index.html", {
        "current_user": user, "page": "index",
        "recipes": recipes, "categories": CATEGORIES,
        "sort_options": _INDEX_SORT_OPTIONS,
        "current_category": category, "current_q": q, "current_sort": sort,
        "today_meals": today_meals,
    })


@router.get("/login", response_class=HTMLResponse)
def login(request: Request, user=Depends(page_user)):
    if user:
        return RedirectResponse("/", status_code=303)
    # 读取登录背景图（公开设置，允许 SSR 注入进 style 里，避免登录页再发一次 fetch）
    from app.config import get_setting as _gs, absolute_url as _abs
    login_bg_raw = (_gs("login_bg_image", "") or "").strip()
    login_bg = _abs(login_bg_raw) if login_bg_raw else ""
    return templates.TemplateResponse(request, "login.html", {
        "current_user": user, "page": "login",
        "login_bg_image": login_bg,
    })


SORT_OPTIONS = [
    ("added_desc",  "最近收藏"),
    ("added_asc",   "最早收藏"),
    ("alpha",       "菜名 A→Z"),
    ("cook_time",   "烹饪时间短→长"),
    ("created_desc","创建时间新→旧"),
]


@router.get("/recipes/favorites", response_class=HTMLResponse)
def favorites(request: Request, user=Depends(page_user)):
    if not user:
        return RedirectResponse("/login", status_code=303)
    category = request.query_params.get("category") or ""
    q = request.query_params.get("q") or ""
    sort = request.query_params.get("sort") or "added_desc"
    conn = _conn()
    try:
        recipes = _list_favorites(conn, user["id"], category or None, q or None, sort)
    finally:
        conn.close()
    return templates.TemplateResponse(request, "index.html", {
        "current_user": user, "page": "favorites",
        "recipes": recipes, "categories": CATEGORIES,
        "sort_options": SORT_OPTIONS,
        "current_category": category, "current_q": q, "current_sort": sort,
    })


def _load_sys_settings(conn):
    rows = conn.execute("SELECT key, value FROM system_settings").fetchall()
    settings = {r["key"]: r["value"] for r in rows}
    defaults = {
        "image_provider": "pixabay",
        "pixabay_api_key": "",
        "proxy_url": "",
        "login_bg_image": "",
        "site_name": "今天吃点啥",
        "public_base_url": "",
    }
    for k, v in defaults.items():
        settings.setdefault(k, v)
    return settings


@router.get("/recipes/new", response_class=HTMLResponse)
def new_recipe(request: Request, user=Depends(page_user)):
    if not user:
        return RedirectResponse("/login", status_code=303)
    conn = _conn()
    try:
        settings = _load_sys_settings(conn)
    finally:
        conn.close()
    return templates.TemplateResponse(request, "edit.html", {
        "current_user": user, "page": "edit",
        "mode": "new", "recipe_id": None,
        "image_provider": settings.get("image_provider", "pixabay"),
    })


@router.get("/recipes/{recipe_id}/edit", response_class=HTMLResponse)
def edit_recipe(request: Request, recipe_id: int, user=Depends(page_user)):
    if not user:
        return RedirectResponse("/login", status_code=303)
    conn = _conn()
    try:
        settings = _load_sys_settings(conn)
    finally:
        conn.close()
    return templates.TemplateResponse(request, "edit.html", {
        "current_user": user, "page": "edit",
        "mode": "edit", "recipe_id": recipe_id,
        "image_provider": settings.get("image_provider", "pixabay"),
    })


@router.get("/recipes/{recipe_id}", response_class=HTMLResponse)
def detail(request: Request, recipe_id: int, user=Depends(page_user)):
    if not user:
        return RedirectResponse("/login", status_code=303)
    conn = _conn()
    try:
        recipe = _get_recipe(conn, user["id"], recipe_id)
    finally:
        conn.close()
    if not recipe:
        return RedirectResponse("/", status_code=303)
    return templates.TemplateResponse(request, "detail.html", {
        "current_user": user, "page": "detail",
        "recipe": recipe, "recipe_id": recipe_id,
    })


@router.get("/admin", response_class=HTMLResponse)
@router.get("/admin/users", response_class=HTMLResponse)
def admin_users(request: Request, user=Depends(page_user)):
    if not user:
        return RedirectResponse("/login", status_code=303)
    if not user["is_admin"]:
        return RedirectResponse("/", status_code=303)
    conn = _conn()
    try:
        users = _list_users(conn)
        rows = conn.execute("SELECT key, value FROM system_settings").fetchall()
        settings = {r["key"]: r["value"] for r in rows}
    finally:
        conn.close()
    # 种子值兜底（确保每一个 key 都有默认值给表单展示）
    defaults = {
        "public_base_url": "http://localhost:8765",
        "site_name": "今天吃点啥",
        "pixabay_api_key": "",
        "image_provider": "pixabay",
        "proxy_url": "",
        "proxy_test_url": "https://pixabay.com/api/docs/",
        "login_bg_image": "",
        "recipe_source": "themealdb",
        "recipe_translate": "1",
    }
    for k, v in defaults.items():
        settings.setdefault(k, v)
    return templates.TemplateResponse(request, "admin.html", {
        "current_user": user, "page": "admin", "users": users,
        "settings": settings, "tab": request.query_params.get("tab", "users"),
    })


@router.get("/profile", response_class=HTMLResponse)
def profile(request: Request, user=Depends(page_user)):
    if not user:
        return RedirectResponse("/login", status_code=303)
    return templates.TemplateResponse(request, "profile.html", {
        "current_user": user, "page": "profile",
    })


@router.get("/about", response_class=HTMLResponse)
def about(request: Request, user=Depends(page_user)):
    if not user:
        return RedirectResponse("/login", status_code=303)
    return templates.TemplateResponse(request, "about.html", {
        "current_user": user, "page": "about",
    })


@router.get("/calendar", response_class=HTMLResponse)
def calendar(request: Request, user=Depends(page_user)):
    if not user:
        return RedirectResponse("/login", status_code=303)
    return templates.TemplateResponse(request, "calendar.html", {
        "current_user": user, "page": "calendar",
    })
