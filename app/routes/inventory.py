"""食材库存路由 /api/inventory/*。"""
import sqlite3
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.auth import get_current_user
from app.database import get_db

router = APIRouter(prefix="/api/inventory", tags=["inventory"])


class InventoryIn(BaseModel):
    name: str = Field(min_length=1, max_length=50)
    amount: Optional[str] = None
    unit: Optional[str] = None


@router.get("")
def list_inventory(
    q: Optional[str] = Query(None),
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    rows = db.execute(
        "SELECT id, name, amount, unit FROM inventory WHERE user_id = ? ORDER BY id DESC",
        (user["id"],),
    ).fetchall()
    return {"items": [dict(r) for r in rows]}


@router.post("")
def add_inventory(
    body: InventoryIn,
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="食材名不能为空")
    db.execute(
        "INSERT OR IGNORE INTO inventory (user_id, name, amount, unit) VALUES (?, ?, ?, ?)",
        (user["id"], name, body.amount, body.unit),
    )
    db.commit()
    return {"ok": True}


@router.delete("/{item_id}")
def remove_inventory(
    item_id: int,
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    db.execute("DELETE FROM inventory WHERE id = ? AND user_id = ?", (item_id, user["id"]))
    db.commit()
    return {"ok": True}
