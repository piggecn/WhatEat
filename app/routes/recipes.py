"""食谱路由 /api/recipes/*。"""
import json as _json
import sqlite3
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app import models
from app.auth import get_current_user
from app.config import absolute_url
from app.database import get_db

router = APIRouter(prefix="/api/recipes", tags=["recipes"])

VALID_CATEGORIES = {"早餐", "午餐", "晚餐", "甜点", "小吃", "饮品"}
VALID_MEAL_TYPES = {"breakfast", "lunch", "dinner"}


def _parse_meal_tags(raw: Optional[str]) -> list:
    """meal_tags 列是 JSON 字符串，解析成 list。"""
    if not raw:
        return []
    try:
        v = _json.loads(raw)
        if isinstance(v, list):
            return [t for t in v if t in VALID_MEAL_TYPES]
    except Exception:
        pass
    return []


def _dump_meal_tags(tags) -> str:
    """序列化 meal_tags list 为 JSON 字符串。"""
    clean = [t for t in (tags or []) if t in VALID_MEAL_TYPES]
    if not clean:
        return ""
    return _json.dumps(clean, ensure_ascii=False)


def _enrich_recipe(item: dict) -> dict:
    """给 recipe dict 附加 image_url 和 (可能的) author_avatar_url。"""
    item["image_url"] = absolute_url(item.get("image_path"))
    av = item.get("author_avatar")
    if isinstance(av, str) and av.startswith("/uploads/"):
        item["author_avatar_url"] = absolute_url(av)
    return item


def _row_to_item(row: sqlite3.Row) -> dict:
    return _enrich_recipe({
        "id": row["id"],
        "title": row["title"],
        "description": row["description"],
        "category": row["category"],
        "meal_tags": _parse_meal_tags(row["meal_tags"] if "meal_tags" in row.keys() else None),
        "image_path": row["image_path"],
        "prep_time": row["prep_time"],
        "cook_time": row["cook_time"],
        "author": row["author"],
        "author_display_name": row["author_display_name"] if "author_display_name" in row.keys() else None,
        "author_avatar": row["author_avatar"] if "author_avatar" in row.keys() else None,
        "is_favorite": bool(row["is_favorite"]),
        "created_at": row["created_at"],
    })


# ---- 列表 ----
@router.get("")
def list_recipes(
    page: Optional[int] = Query(None, ge=1),
    limit: Optional[int] = Query(None, ge=1, le=100),
    category: Optional[str] = None,
    q: Optional[str] = None,
    meal_type: Optional[str] = None,
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    if category is not None and category not in VALID_CATEGORIES:
        raise HTTPException(status_code=400, detail=f"无效分类，可选: {', '.join(sorted(VALID_CATEGORIES))}")
    if meal_type is not None and meal_type not in VALID_MEAL_TYPES:
        raise HTTPException(status_code=400, detail=f"无效 meal_type")

    where = []
    params: list = []
    if category:
        where.append("r.category = ?")
        params.append(category)
    if meal_type:
        where.append("r.meal_tags LIKE ?")
        params.append(f'%"{meal_type}"%')
    if q:
        where.append("(r.title LIKE ? OR r.description LIKE ?)")
        params.extend([f"%{q}%", f"%{q}%"])
    where_sql = (" WHERE " + " AND ".join(where)) if where else ""

    paginated = (page is not None) or (limit is not None)

    if not paginated:
        # 向后兼容：无分页参数时返回纯列表，无包装
        rows = db.execute(
            f"""
            SELECT r.id, r.title, r.description, r.category, r.meal_tags, r.image_path,
                   r.prep_time, r.cook_time, r.created_at,
                   u.username AS author,
                   u.display_name AS author_display_name,
                   u.avatar AS author_avatar,
                   EXISTS(SELECT 1 FROM favorites f WHERE f.user_id = ? AND f.recipe_id = r.id) AS is_favorite
            FROM recipes r
            JOIN users u ON u.id = r.created_by
            {where_sql}
            ORDER BY r.created_at DESC
            """,
            [user["id"]] + params,
        ).fetchall()
        return [_row_to_item(r) for r in rows]

    # 分页模式
    eff_page = page if page is not None else 1
    eff_limit = limit if limit is not None else 20
    if eff_page < 1:
        raise HTTPException(status_code=400, detail="page 必须 >= 1")
    if not (1 <= eff_limit <= 100):
        raise HTTPException(status_code=400, detail="limit 必须在 1-100 之间")

    total = db.execute(
        f"SELECT COUNT(*) AS c FROM recipes r{where_sql}", params
    ).fetchone()["c"]

    offset = (eff_page - 1) * eff_limit
    rows = db.execute(
        f"""
        SELECT r.id, r.title, r.description, r.category, r.meal_tags, r.image_path,
               r.prep_time, r.cook_time, r.created_at,
               u.username AS author,
               u.display_name AS author_display_name,
               u.avatar AS author_avatar,
               EXISTS(SELECT 1 FROM favorites f WHERE f.user_id = ? AND f.recipe_id = r.id) AS is_favorite
        FROM recipes r
        JOIN users u ON u.id = r.created_by
        {where_sql}
        ORDER BY r.created_at DESC
        LIMIT ? OFFSET ?
        """,
        [user["id"]] + params + [eff_limit, offset],
    ).fetchall()
    items = [_row_to_item(r) for r in rows]
    return {
        "items": items,
        "total": total,
        "page": eff_page,
        "limit": eff_limit,
        "has_more": (eff_page * eff_limit) < total,
    }


# ---- 我的收藏（必须在 /{id} 之前） ----
@router.get("/favorites", response_model=models.RecipeListResponse)
def list_favorites(
    page: int = Query(1, ge=1),
    page_size: int = Query(12, ge=1, le=100),
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    total = db.execute(
        "SELECT COUNT(*) AS c FROM favorites WHERE user_id = ?", (user["id"],)
    ).fetchone()["c"]
    offset = (page - 1) * page_size
    rows = db.execute(
        """
        SELECT r.id, r.title, r.description, r.category, r.meal_tags, r.image_path,
               r.prep_time, r.cook_time, r.created_at,
               u.username AS author,
               u.display_name AS author_display_name,
               u.avatar AS author_avatar,
               1 AS is_favorite
        FROM favorites fav
        JOIN recipes r ON r.id = fav.recipe_id
        JOIN users u ON u.id = r.created_by
        WHERE fav.user_id = ?
        ORDER BY fav.id DESC
        LIMIT ? OFFSET ?
        """,
        (user["id"], page_size, offset),
    ).fetchall()
    return {
        "total": total,
        "page": page,
        "page_size": page_size,
        "items": [_row_to_item(r) for r in rows],
    }


# ---- 详情 ----
@router.get("/{recipe_id}", response_model=models.RecipeDetail)
def get_recipe(
    recipe_id: int,
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    row = db.execute(
        """
        SELECT r.*, u.username AS author, u.display_name AS author_display_name,
               u.avatar AS author_avatar,
               EXISTS(SELECT 1 FROM favorites f WHERE f.user_id = ? AND f.recipe_id = r.id) AS is_favorite
        FROM recipes r
        JOIN users u ON u.id = r.created_by
        WHERE r.id = ?
        """,
        (user["id"], recipe_id),
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="食谱不存在")
    ingredients = [
        {"id": i["id"], "name": i["name"], "amount": i["amount"], "unit": i["unit"]}
        for i in db.execute(
            "SELECT * FROM ingredients WHERE recipe_id = ? ORDER BY id", (recipe_id,)
        ).fetchall()
    ]
    steps = [
        {"id": s["id"], "step_number": s["step_number"], "description": s["description"]}
        for s in db.execute(
            "SELECT * FROM steps WHERE recipe_id = ? ORDER BY step_number", (recipe_id,)
        ).fetchall()
    ]
    return _enrich_recipe({
        "id": row["id"],
        "title": row["title"],
        "description": row["description"],
        "category": row["category"],
        "meal_tags": _parse_meal_tags(row["meal_tags"] if "meal_tags" in row.keys() else None),
        "servings": row["servings"],
        "prep_time": row["prep_time"],
        "cook_time": row["cook_time"],
        "image_path": row["image_path"],
        "created_by": row["created_by"],
        "author": row["author"],
        "author_display_name": row["author_display_name"] if "author_display_name" in row.keys() else None,
        "author_avatar": row["author_avatar"] if "author_avatar" in row.keys() else None,
        "is_favorite": bool(row["is_favorite"]),
        "ingredients": ingredients,
        "steps": steps,
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    })


# ---- 创建 ----
@router.post("", response_model=models.RecipeDetail, status_code=201)
def create_recipe(
    body: models.RecipeCreate,
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    if body.category and body.category not in VALID_CATEGORIES:
        raise HTTPException(status_code=400, detail=f"无效分类，可选: {', '.join(sorted(VALID_CATEGORIES))}")
    # meal_tags 默认值兜底：如果用户没传，按 category 推导
    meal_tags = body.meal_tags if body.meal_tags else _default_tags_from_category(body.category)

    cur = db.execute(
        """
        INSERT INTO recipes (title, description, category, meal_tags, servings, prep_time, cook_time, image_path, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            body.title,
            body.description,
            body.category,
            _dump_meal_tags(meal_tags),
            body.servings,
            body.prep_time,
            body.cook_time,
            body.image_path,
            user["id"],
        ),
    )
    recipe_id = cur.lastrowid
    _persist_children(db, recipe_id, body.ingredients, body.steps)
    db.commit()
    return get_recipe(recipe_id, db, user)


def _default_tags_from_category(category: Optional[str]) -> list:
    if category == "早餐":
        return ["breakfast"]
    if category == "午餐":
        return ["lunch"]
    if category == "晚餐":
        return ["dinner"]
    if category in ("甜点", "小吃"):
        return ["lunch", "dinner"]
    if category == "饮品":
        return ["breakfast", "lunch", "dinner"]
    return ["lunch", "dinner"]


def _persist_children(db: sqlite3.Connection, recipe_id: int, ingredients, steps):
    db.executemany(
        "INSERT INTO ingredients (recipe_id, name, amount, unit) VALUES (?, ?, ?, ?)",
        [
            (recipe_id, ing.name, ing.amount, ing.unit)
            for ing in ingredients
        ],
    )
    db.executemany(
        "INSERT INTO steps (recipe_id, step_number, description) VALUES (?, ?, ?)",
        [
            (recipe_id, i + 1, st.description)
            for i, st in enumerate(steps)
        ],
    )


# ---- 更新 ----
@router.put("/{recipe_id}", response_model=models.RecipeDetail)
def update_recipe(
    recipe_id: int,
    body: models.RecipeUpdate,
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    row = db.execute("SELECT * FROM recipes WHERE id = ?", (recipe_id,)).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="食谱不存在")
    if row["created_by"] != user["id"] and not user["is_admin"]:
        raise HTTPException(status_code=403, detail="无权修改他人食谱")
    if body.category and body.category not in VALID_CATEGORIES:
        raise HTTPException(status_code=400, detail=f"无效分类，可选: {', '.join(sorted(VALID_CATEGORIES))}")
    meal_tags = body.meal_tags if body.meal_tags else _default_tags_from_category(body.category)

    db.execute(
        """
        UPDATE recipes SET title=?, description=?, category=?, meal_tags=?, servings=?, prep_time=?,
        cook_time=?, image_path=?, updated_at=CURRENT_TIMESTAMP WHERE id=?
        """,
        (
            body.title,
            body.description,
            body.category,
            _dump_meal_tags(meal_tags),
            body.servings,
            body.prep_time,
            body.cook_time,
            body.image_path,
            recipe_id,
        ),
    )
    db.execute("DELETE FROM ingredients WHERE recipe_id = ?", (recipe_id,))
    db.execute("DELETE FROM steps WHERE recipe_id = ?", (recipe_id,))
    _persist_children(db, recipe_id, body.ingredients, body.steps)
    db.commit()
    return get_recipe(recipe_id, db, user)


# ---- 删除 ----
@router.delete("/{recipe_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_recipe(
    recipe_id: int,
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    row = db.execute("SELECT * FROM recipes WHERE id = ?", (recipe_id,)).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="食谱不存在")
    if row["created_by"] != user["id"] and not user["is_admin"]:
        raise HTTPException(status_code=403, detail="无权删除他人食谱")
    db.execute("DELETE FROM recipes WHERE id = ?", (recipe_id,))
    db.commit()
    return None


# ---- 收藏/取消 ----
@router.post("/{recipe_id}/favorite")
def toggle_favorite(
    recipe_id: int,
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    if not db.execute("SELECT 1 FROM recipes WHERE id = ?", (recipe_id,)).fetchone():
        raise HTTPException(status_code=404, detail="食谱不存在")
    existing = db.execute(
        "SELECT id FROM favorites WHERE user_id = ? AND recipe_id = ?",
        (user["id"], recipe_id),
    ).fetchone()
    if existing:
        db.execute("DELETE FROM favorites WHERE id = ?", (existing["id"],))
        db.commit()
        return {"is_favorite": False}
    db.execute(
        "INSERT INTO favorites (user_id, recipe_id) VALUES (?, ?)",
        (user["id"], recipe_id),
    )
    db.commit()
    return {"is_favorite": True}
