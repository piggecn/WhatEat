"""日历路由 /api/calendar/*。"""
import re
import sqlite3
import calendar as cal
from collections import defaultdict
from datetime import date as date_cls, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query

from app import models
from app.auth import get_current_user
from app.database import get_db

router = APIRouter(prefix="/api/calendar", tags=["calendar"])

VALID_MEAL_TYPES = {"breakfast", "lunch", "dinner"}
WEEKDAYS = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]


def _get_week_range(date_str: str) -> tuple[date_cls, date_cls]:
    """传入日期，返回当周（周一起周日止）的起止日期。"""
    try:
        d = date_cls.fromisoformat(date_str)
    except ValueError:
        raise HTTPException(status_code=400, detail="date 必须为 YYYY-MM-DD 格式")
    monday = d - timedelta(days=d.weekday())
    sunday = monday + timedelta(days=6)
    return monday, sunday


def _to_image_url(image_path: Optional[str]) -> Optional[str]:
    if not image_path:
        return None
    if image_path.startswith("http://") or image_path.startswith("https://") or image_path.startswith("/"):
        return image_path
    return f"/uploads/{image_path}"


@router.get("/week", response_model=models.WeekPlanResponse)
def get_week_plan(
    date: str = Query(..., description="参考日期 YYYY-MM-DD"),
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    monday, sunday = _get_week_range(date)
    days_result = []
    for i in range(7):
        cur_date = monday + timedelta(days=i)
        date_iso = cur_date.isoformat()
        day = {
            "date": date_iso,
            "weekday": WEEKDAYS[i],
            "breakfast": [],
            "lunch": [],
            "dinner": [],
        }
        rows = db.execute(
            """
            SELECT mp.meal_type, mp.recipe_id, r.title, r.image_path
            FROM meal_plans mp
            LEFT JOIN recipes r ON r.id = mp.recipe_id
            WHERE mp.user_id = ? AND mp.date = ?
            """,
            (user["id"], date_iso),
        ).fetchall()
        for r in rows:
            mt = r["meal_type"]
            if mt in VALID_MEAL_TYPES:
                day[mt].append({
                    "recipe_id": r["recipe_id"],
                    "title": r["title"],
                    "image_url": _to_image_url(r["image_path"]),
                })
        days_result.append(day)
    return {"days": days_result}


@router.post("/plan")
def create_plan(
    body: models.CalendarPlanCreate,
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    if body.meal_type not in VALID_MEAL_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"无效 meal_type，可选: {', '.join(sorted(VALID_MEAL_TYPES))}",
        )
    try:
        date_cls.fromisoformat(body.date)
    except ValueError:
        raise HTTPException(status_code=400, detail="date 必须为 YYYY-MM-DD 格式")
    if not db.execute("SELECT 1 FROM recipes WHERE id = ?", (body.recipe_id,)).fetchone():
        raise HTTPException(status_code=404, detail="食谱不存在")

    dup = db.execute(
        "SELECT id FROM meal_plans WHERE user_id = ? AND date = ? AND meal_type = ? AND recipe_id = ?",
        (user["id"], body.date, body.meal_type, body.recipe_id),
    ).fetchone()
    if not dup:
        db.execute(
            "INSERT INTO meal_plans (user_id, date, meal_type, recipe_id, is_planned) VALUES (?, ?, ?, ?, 1)",
            (user["id"], body.date, body.meal_type, body.recipe_id),
        )
        db.commit()
    return {"ok": True}


@router.delete("/plan")
def delete_plan(
    date: Optional[str] = Query(None, description="YYYY-MM-DD（查询参数，前端使用）"),
    meal_type: Optional[str] = Query(None, description="breakfast/lunch/dinner"),
    recipe_id: Optional[int] = Query(None, description="指定删除某一道菜；不传则删除该餐全部"),
    body: Optional[models.CalendarPlanDelete] = None,
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    d = date or (body.date if body else None)
    mt = meal_type or (body.meal_type if body else None)
    if not d or not mt:
        raise HTTPException(status_code=400, detail="缺少 date / meal_type")
    if mt not in VALID_MEAL_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"无效 meal_type，可选: {', '.join(sorted(VALID_MEAL_TYPES))}",
        )
    try:
        date_cls.fromisoformat(d)
    except ValueError:
        raise HTTPException(status_code=400, detail="date 必须为 YYYY-MM-DD 格式")

    if recipe_id is not None:
        db.execute(
            "DELETE FROM meal_plans WHERE user_id = ? AND date = ? AND meal_type = ? AND recipe_id = ?",
            (user["id"], d, mt, recipe_id),
        )
    else:
        db.execute(
            "DELETE FROM meal_plans WHERE user_id = ? AND date = ? AND meal_type = ?",
            (user["id"], d, mt),
        )
    db.commit()
    return {"ok": True}


@router.get("/month", response_model=models.MonthPlanResponse)
def get_month_plan(
    month: str = Query(..., description="参考月份 YYYY-MM"),
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    try:
        year, month_num = month.split("-")
        year = int(year)
        month_num = int(month_num)
        if not (1 <= month_num <= 12):
            raise ValueError
    except (ValueError, AttributeError):
        raise HTTPException(status_code=400, detail="month 必须为 YYYY-MM 格式")

    _, last_day = cal.monthrange(year, month_num)
    start_date = date_cls(year, month_num, 1)
    end_date = date_cls(year, month_num, last_day)

    plan_rows = db.execute(
        """
        SELECT mp.date, mp.meal_type, r.id AS recipe_id, r.title, r.image_path
        FROM meal_plans mp
        LEFT JOIN recipes r ON r.id = mp.recipe_id
        WHERE mp.user_id = ? AND mp.date >= ? AND mp.date <= ?
        """,
        (user["id"], start_date.isoformat(), end_date.isoformat()),
    ).fetchall()
    plan_map = defaultdict(lambda: defaultdict(list))
    for r in plan_rows:
        plan_map[r["date"]][r["meal_type"]].append({
            "recipe_id": r["recipe_id"],
            "title": r["title"],
            "image_url": _to_image_url(r["image_path"]),
        })

    meal_rows = db.execute(
        """
        SELECT m.date, m.meal_type
        FROM meals m
        WHERE m.user_id = ? AND m.date >= ? AND m.date <= ?
        """,
        (user["id"], start_date.isoformat(), end_date.isoformat()),
    ).fetchall()
    meal_map = defaultdict(set)
    for r in meal_rows:
        meal_map[r["date"]].add(r["meal_type"])

    days_result = []
    for day in range(1, last_day + 1):
        cur_date = date_cls(year, month_num, day).isoformat()
        planned = plan_map.get(cur_date, {})
        ate = meal_map.get(cur_date, set())
        b = planned.get("breakfast", [])
        l = planned.get("lunch", [])
        d = planned.get("dinner", [])
        days_result.append({
            "date": cur_date,
            "has_records": len(ate) > 0,
            "has_plans": len(planned) > 0,
            "breakfast_planned": "breakfast" in ate or bool(b),
            "lunch_planned": "lunch" in ate or bool(l),
            "dinner_planned": "dinner" in ate or bool(d),
            "breakfast_ate": "breakfast" in ate,
            "lunch_ate": "lunch" in ate,
            "dinner_ate": "dinner" in ate,
            "breakfast": b,
            "lunch": l,
            "dinner": d,
        })
    return {"year": year, "month": month_num, "days": days_result}


@router.get("/shopping-list", response_model=models.ShoppingListResponse)
def get_shopping_list(
    date: Optional[str] = Query(None, description="参考日期 YYYY-MM-DD（当周起算）"),
    week_start: Optional[str] = Query(None, description="兼容前端参数 week_start"),
    db: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    ref = date or week_start
    if not ref:
        raise HTTPException(status_code=400, detail="缺少参考日期")
    monday, sunday = _get_week_range(ref)

    plan_rows = db.execute(
        """
        SELECT DISTINCT mp.recipe_id
        FROM meal_plans mp
        WHERE mp.user_id = ? AND mp.date >= ? AND mp.date <= ? AND mp.recipe_id IS NOT NULL
        """,
        (user["id"], monday.isoformat(), sunday.isoformat()),
    ).fetchall()
    recipe_ids = [r["recipe_id"] for r in plan_rows]

    MEAL_LABEL = {"breakfast": "早餐", "lunch": "午餐", "dinner": "晚餐"}

    def _ing_items(rid: int) -> list:
        rows = db.execute(
            "SELECT name, amount, unit FROM ingredients WHERE recipe_id = ? ORDER BY id", (rid,)
        ).fetchall()
        merged = defaultdict(lambda: {"amounts": set(), "unit": None, "numeric": []})
        for r in rows:
            key = r["name"]
            if r["amount"]:
                raw = str(r["amount"]).strip()
                merged[key]["amounts"].add(raw)
                m = re.match(r"^(\d+(?:\.\d+)?)(.*)$", raw)
                if m and not m.group(2).strip():
                    merged[key]["numeric"].append(float(m.group(1)))
            if r["unit"] and not merged[key]["unit"]:
                merged[key]["unit"] = r["unit"]
        items = []
        for name, data in merged.items():
            total = None
            if len(data["numeric"]) == len(data["amounts"]) and data["numeric"]:
                sm = sum(data["numeric"])
                total = str(int(sm)) if abs(sm - round(sm)) < 1e-9 else f"{sm:.2f}".rstrip("0").rstrip(".")
            items.append({"name": name, "amounts": sorted(data["amounts"]), "total": total, "unit": data["unit"]})
        return items

    # 按天分组
    by_day = []
    if recipe_ids:
        day_rows = db.execute(
            f"""
            SELECT mp.date, mp.meal_type, mp.recipe_id, r.title
            FROM meal_plans mp
            JOIN recipes r ON r.id = mp.recipe_id
            WHERE mp.user_id = ? AND mp.date >= ? AND mp.date <= ?
            ORDER BY mp.date, mp.meal_type, mp.id
            """,
            (user["id"], monday.isoformat(), sunday.isoformat()),
        ).fetchall()
        by_date = defaultdict(lambda: defaultdict(list))
        for r in day_rows:
            by_date[r["date"]][r["meal_type"]].append({"recipe_id": r["recipe_id"], "title": r["title"]})
        for i in range(7):
            cur = monday + timedelta(days=i)
            dkey = cur.isoformat()
            meals = []
            for mt in VALID_MEAL_TYPES:
                entries = by_date.get(dkey, {}).get(mt, [])
                if not entries:
                    continue
                meals.append({
                    "meal_type": mt,
                    "label": MEAL_LABEL[mt],
                    "recipes": [e["title"] for e in entries],
                    "items": [item for e in entries for item in _ing_items(e["recipe_id"])],
                })
            if meals:
                by_day.append({"date": dkey, "weekday": WEEKDAYS[i], "meals": meals})

    if not recipe_ids:
        return {"items": [], "by_day": []}

    placeholders = ",".join(["?"] * len(recipe_ids))
    ing_rows = db.execute(
        f"""
        SELECT name, amount, unit FROM ingredients
        WHERE recipe_id IN ({placeholders})
        ORDER BY name
        """,
        recipe_ids,
    ).fetchall()

    merged = defaultdict(lambda: {"amounts": set(), "unit": None, "numeric": []})
    for r in ing_rows:
        key = r["name"]
        if r["amount"]:
            raw = str(r["amount"]).strip()
            merged[key]["amounts"].add(raw)
            m = re.match(r"^(\d+(?:\.\d+)?)(.*)$", raw)
            if m and not m.group(2).strip():
                merged[key]["numeric"].append(float(m.group(1)))
        if r["unit"] and not merged[key]["unit"]:
            merged[key]["unit"] = r["unit"]

    items = []
    for name, data in merged.items():
        total = None
        if len(data["numeric"]) == len(data["amounts"]) and data["numeric"]:
            s = sum(data["numeric"])
            total = str(int(s)) if abs(s - round(s)) < 1e-9 else f"{s:.2f}".rstrip("0").rstrip(".")
        items.append({
            "name": name,
            "amounts": sorted(data["amounts"]),
            "total": total,
            "unit": data["unit"],
        })
    return {"items": items, "by_day": by_day}
