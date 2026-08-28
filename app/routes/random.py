"""随机推荐路由 /api/recipes/random。"""
import json as _json
import sqlite3
from datetime import date as date_cls, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query

from app import models
from app.auth import get_current_user
from app.config import absolute_url
from app.database import get_db

router = APIRouter(prefix="/api/recipes", tags=["random"])

VALID_CATEGORIES = {"早餐", "午餐", "晚餐", "甜点", "小吃", "饮品"}
VALID_MEAL_TYPES = {"breakfast", "lunch", "dinner"}


def _parse_meal_tags(raw: Optional[str]) -> list:
    if not raw:
        return []
    try:
        v = _json.loads(raw)
        if isinstance(v, list):
            return [t for t in v if t in VALID_MEAL_TYPES]
    except Exception:
        pass
    return []


def _enrich_recipe(item: dict) -> dict:
    item["image_url"] = absolute_url(item.get("image_path"))
    av = item.get("author_avatar")
    if isinstance(av, str) and av.startswith("/uploads/"):
        item["author_avatar_url"] = absolute_url(av)
    return item


def _count_eligible(db, user_id: int, category: Optional[str], meal_type: Optional[str], exclude_days: int) -> int:
    where, params = [], []
    if category:
        where.append("r.category = ?")
        params.append(category)
    if meal_type:
        where.append("r.meal_tags LIKE ?")
        params.append(f'%"{meal_type}"%')
    if exclude_days > 0:
        cutoff = (date_cls.today() - timedelta(days=exclude_days)).isoformat()
        where.append(
            "r.id NOT IN (SELECT DISTINCT recipe_id FROM meals WHERE user_id = ? AND date >= ?)"
        )
        params.extend([user_id, cutoff])
    where_sql = (" WHERE " + " AND ".join(where)) if where else ""
    row = db.execute(
        f"SELECT COUNT(*) AS c FROM recipes r{where_sql}", params
    ).fetchone()
    return int(row["c"] or 0)


@router.get("/random", response_model=models.RecipeDetail)
def get_random_recipe(
    category: Optional[str] = None,
    meal_type: Optional[str] = None,
    exclude_recent_days: int = Query(0, ge=0, le=365),
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    """从 recipes 表随机取 1 条。
    - category 指定时，只在该分类里随机（兼容旧接口）
    - meal_type 指定时，按 meal_tags 包含性筛选（推荐）
    - exclude_recent_days > 0 时，排除最近 N 天 meals 表里有记录的 recipe_id
    - 总食谱数 < 5 时自动忽略 exclude_recent_days
    - 按条件查询为空时自动 fallback：先忽略 exclude，再忽略 meal_type/category
    - 全部为空才返回 empty=true + 提示
    """
    if category is not None and category not in VALID_CATEGORIES:
        raise HTTPException(
            status_code=400,
            detail=f"无效分类，可选: {', '.join(sorted(VALID_CATEGORIES))}",
        )
    if meal_type is not None and meal_type not in VALID_MEAL_TYPES:
        raise HTTPException(status_code=400, detail="无效 meal_type")

    total_count = int(db.execute("SELECT COUNT(*) AS c FROM recipes").fetchone()["c"] or 0)

    # 食谱数 < 5 自动放宽排除条件
    eff_exclude = exclude_recent_days if total_count >= 5 else 0

    # 总候选数（在原始筛选下），用于前端提示
    total_eligible = _count_eligible(db, user["id"], category, meal_type, eff_exclude)

    # 尝试顺序：用户参数 → 忽略 exclude → 忽略 meal_type
    # 注意：不 fallback 到忽略 category，否则选了分类还返回其他分类的食谱
    attempts = [
        (category, meal_type, eff_exclude),
        (category, meal_type, 0),
        (category, None, 0),
    ]
    # 去重保持顺序
    seen, ordered = set(), []
    for a in attempts:
        if a not in seen:
            ordered.append(a)
            seen.add(a)

    row = None
    fallback_level = 0
    for idx, (cat, mt, ed) in enumerate(ordered):
        fallback_level = idx
        row = _try_one(db, user["id"], cat, mt, ed)
        if row:
            break

    if not row:
        # 根据是否有筛选条件给出不同提示
        if category or meal_type:
            msg = "这个条件下没有可选的食谱了"
        elif total_count == 0:
            msg = "食谱库里还没有食谱，先去添加一道吧"
        else:
            msg = "没有可选的食谱了"
        return {
            "id": 0, "title": "", "servings": 0, "created_by": 0,
            "author": "", "is_favorite": False, "ingredients": [], "steps": [],
            "created_at": "", "updated_at": "",
            "empty": True, "message": msg,
            "total_eligible": 0,
            "image_url": None,
        }

    recipe_id = row["id"]
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
        "total_eligible": total_eligible,
        "empty": False,
        # fallback_level > 0 时前端可提示「已自动放宽条件」
        "message": "已自动放宽条件为你挑选" if fallback_level > 0 else None,
    })


def _try_one(db: sqlite3.Connection, user_id: int, category: Optional[str], meal_type: Optional[str], exclude_days: int):
    where = []
    params: list = []
    if category:
        where.append("r.category = ?")
        params.append(category)
    if meal_type:
        where.append("r.meal_tags LIKE ?")
        params.append(f'%"{meal_type}"%')
    if exclude_days > 0:
        cutoff = (date_cls.today() - timedelta(days=exclude_days)).isoformat()
        where.append(
            "r.id NOT IN (SELECT DISTINCT recipe_id FROM meals WHERE user_id = ? AND date >= ?)"
        )
        params.extend([user_id, cutoff])
    where_sql = (" WHERE " + " AND ".join(where)) if where else ""
    return db.execute(
        f"""
        SELECT r.*, u.username AS author, u.display_name AS author_display_name, u.avatar AS author_avatar,
               EXISTS(SELECT 1 FROM favorites f WHERE f.user_id = ? AND f.recipe_id = r.id) AS is_favorite
        FROM recipes r
        JOIN users u ON u.id = r.created_by
        {where_sql}
        ORDER BY RANDOM()
        LIMIT 1
        """,
        [user_id] + params,
    ).fetchone()
