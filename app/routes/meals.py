"""用餐记录路由 /api/meals/*。"""
import sqlite3
from datetime import date as date_cls, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app import models
from app.auth import get_current_user
from app.database import get_db

router = APIRouter(prefix="/api/meals", tags=["meals"])

VALID_MEAL_TYPES = {"breakfast", "lunch", "dinner"}


@router.post("", response_model=models.MealResponse, status_code=201)
def create_meal(
    body: models.MealCreate,
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    """记录一顿饭：{recipe_id, meal_type, date}。"""
    if body.meal_type not in VALID_MEAL_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"无效 meal_type，可选: {', '.join(sorted(VALID_MEAL_TYPES))}",
        )
    # 校验日期格式 YYYY-MM-DD
    try:
        date_cls.fromisoformat(body.date)
    except ValueError:
        raise HTTPException(status_code=400, detail="date 必须为 YYYY-MM-DD 格式")

    if not db.execute("SELECT 1 FROM recipes WHERE id = ?", (body.recipe_id,)).fetchone():
        raise HTTPException(status_code=404, detail="食谱不存在")

    cur = db.execute(
        "INSERT INTO meals (user_id, recipe_id, meal_type, date) VALUES (?, ?, ?, ?)",
        (user["id"], body.recipe_id, body.meal_type, body.date),
    )
    db.commit()
    meal_id = cur.lastrowid
    r = db.execute(
        """
        SELECT m.id, m.user_id, m.recipe_id, m.meal_type, m.date, m.created_at,
               r.title AS recipe_title, r.image_path AS recipe_image
        FROM meals m
        LEFT JOIN recipes r ON r.id = m.recipe_id
        WHERE m.id = ?
        """,
        (meal_id,),
    ).fetchone()
    return _row_to_response(r)


@router.get("", response_model=list[models.MealResponse])
def list_meals(
    date: Optional[str] = None,
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    """查询某天用餐列表（不传 date 则返回当前用户全部记录，按时间倒序）。"""
    if date is None:
        rows = db.execute(
            """
            SELECT m.id, m.user_id, m.recipe_id, m.meal_type, m.date, m.created_at,
                   r.title AS recipe_title, r.image_path AS recipe_image
            FROM meals m
            LEFT JOIN recipes r ON r.id = m.recipe_id
            WHERE m.user_id = ?
            ORDER BY m.created_at DESC
            """,
            (user["id"],),
        ).fetchall()
    else:
        rows = db.execute(
            """
            SELECT m.id, m.user_id, m.recipe_id, m.meal_type, m.date, m.created_at,
                   r.title AS recipe_title, r.image_path AS recipe_image
            FROM meals m
            LEFT JOIN recipes r ON r.id = m.recipe_id
            WHERE m.user_id = ? AND m.date = ?
            ORDER BY m.created_at DESC
            """,
            (user["id"], date),
        ).fetchall()
    return [_row_to_response(r) for r in rows]


@router.get("/recent", response_model=list[int])
def recent_meal_recipe_ids(
    days: int = Query(7, ge=1, le=365),
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    """返回最近 N 天吃过的 recipe_id 列表（去重）。"""
    cutoff = (date_cls.today() - timedelta(days=days)).isoformat()
    rows = db.execute(
        """
        SELECT DISTINCT recipe_id
        FROM meals
        WHERE user_id = ? AND date >= ?
        ORDER BY recipe_id
        """,
        (user["id"], cutoff),
    ).fetchall()
    return [r["recipe_id"] for r in rows]


def _row_to_response(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "user_id": row["user_id"],
        "recipe_id": row["recipe_id"],
        "meal_type": row["meal_type"],
        "date": row["date"],
        "created_at": row["created_at"],
        "recipe_title": row["recipe_title"] if "recipe_title" in row.keys() else None,
        "recipe_image": row["recipe_image"] if "recipe_image" in row.keys() else None,
    }


@router.delete("/{meal_id}", status_code=200)
def delete_meal(
    meal_id: int,
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    """删除一条用餐记录。"""
    row = db.execute(
        "SELECT id, user_id FROM meals WHERE id = ?", (meal_id,)
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="用餐记录不存在")
    if row["user_id"] != user["id"]:
        raise HTTPException(status_code=403, detail="无权删除他人的记录")
    db.execute("DELETE FROM meals WHERE id = ?", (meal_id,))
    db.commit()
    return {"ok": True}
