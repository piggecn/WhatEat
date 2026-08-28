"""轮播路由 /api/recipes/carousel。"""
import sqlite3
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query

from app import models
from app.auth import get_current_user
from app.config import absolute_url
from app.database import get_db

router = APIRouter(prefix="/api/recipes", tags=["carousel"])

VALID_TYPES = {"most_cooked", "favorites", "recent", "random"}


@router.get("/carousel", response_model=list[models.CarouselItem])
def get_carousel(
    type: Optional[str] = Query(None, description="most_cooked|favorites|recent|random"),
    limit: Optional[int] = Query(None, ge=5, le=20, description="5-20"),
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    eff_type = type if type else (user["carousel_type"] or "most_cooked")
    eff_limit = limit if limit else (user["carousel_limit"] or 10)

    if eff_type not in VALID_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"无效 type，可选: {', '.join(sorted(VALID_TYPES))}",
        )
    if not (5 <= eff_limit <= 20):
        raise HTTPException(status_code=400, detail="limit 必须在 5-20 之间")

    rows = []
    if eff_type == "most_cooked":
        rows = db.execute(
            """
            SELECT r.id, r.title, r.image_path, r.category, COUNT(m.id) AS cook_count
            FROM recipes r
            LEFT JOIN meals m ON m.recipe_id = r.id AND m.user_id = ?
            GROUP BY r.id
            ORDER BY cook_count DESC, r.created_at DESC
            LIMIT ?
            """,
            (user["id"], eff_limit),
        ).fetchall()
    elif eff_type == "favorites":
        rows = db.execute(
            """
            SELECT r.id, r.title, r.image_path, r.category
            FROM favorites f
            JOIN recipes r ON r.id = f.recipe_id
            WHERE f.user_id = ?
            ORDER BY f.id DESC
            LIMIT ?
            """,
            (user["id"], eff_limit),
        ).fetchall()
    elif eff_type == "recent":
        rows = db.execute(
            """
            SELECT id, title, image_path, category
            FROM recipes
            ORDER BY created_at DESC
            LIMIT ?
            """,
            (eff_limit,),
        ).fetchall()
    else:
        rows = db.execute(
            """
            SELECT id, title, image_path, category
            FROM recipes
            ORDER BY RANDOM()
            LIMIT ?
            """,
            (eff_limit,),
        ).fetchall()

    return [
        {
            "id": r["id"],
            "title": r["title"],
            "image_url": absolute_url(r["image_path"]),
            "category": r["category"],
        }
        for r in rows
    ]
