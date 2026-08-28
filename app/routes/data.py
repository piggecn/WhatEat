"""数据导入 / 导出 / 恢复 接口。

备份范围（仅管理员可导出/导入）：
- 系统设置 system_settings
- 账号 users（含密码哈希，不含明文密码）
- 全部食谱 recipes + ingredients + steps（不限创建者）
- 收藏 favorites、用餐记录 meals、日历预定 meal_plans
"""
import json
import sqlite3
from datetime import date as _date
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from fastapi.responses import StreamingResponse
import io
from app.auth import get_current_user
from app.database import get_db

router = APIRouter(prefix="/api/data", tags=["data"])


def _export_all(conn: sqlite3.Connection) -> dict:
    """导出全部数据（管理员权限）。"""
    data = {"version": 2, "exported_at": _date.today().isoformat()}

    # 系统设置
    data["system_settings"] = {
        r["key"]: r["value"]
        for r in conn.execute("SELECT key, value FROM system_settings").fetchall()
    }

    # 账号（含密码哈希，便于恢复）
    users = conn.execute(
        "SELECT id, username, password_hash, display_name, avatar, is_admin, "
        "carousel_type, carousel_limit, created_at FROM users"
    ).fetchall()
    data["users"] = [dict(u) for u in users]

    # 全部食谱 + 食材/步骤
    recipes = conn.execute("SELECT * FROM recipes").fetchall()
    data["recipes"] = []
    for r in recipes:
        recipe = dict(r)
        recipe["ingredients"] = [dict(x) for x in conn.execute(
            "SELECT name, amount, unit FROM ingredients WHERE recipe_id = ?", (r["id"],)
        ).fetchall()]
        recipe["steps"] = [dict(x) for x in conn.execute(
            "SELECT step_number, description FROM steps WHERE recipe_id = ? ORDER BY step_number", (r["id"],)
        ).fetchall()]
        data["recipes"].append(recipe)

    # 收藏 / 用餐记录 / 日历预定（全部用户）
    data["favorites"] = [dict(x) for x in conn.execute(
        "SELECT user_id, recipe_id FROM favorites").fetchall()]
    data["meals"] = [dict(x) for x in conn.execute(
        "SELECT user_id, meal_type, recipe_id, date FROM meals").fetchall()]
    data["meal_plans"] = [dict(x) for x in conn.execute(
        "SELECT user_id, recipe_id, date, meal_type, is_planned FROM meal_plans").fetchall()]

    return data


@router.get("/export")
def export_data(
    conn: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    """导出全部数据为 JSON 文件（仅管理员）。"""
    if not user["is_admin"]:
        raise HTTPException(status_code=403, detail="只有管理员可以导出完整备份")
    data = _export_all(conn)
    filename = f"recipe-backup-{_date.today().isoformat()}.json"
    content = json.dumps(data, ensure_ascii=False, indent=2)
    return StreamingResponse(
        io.BytesIO(content.encode("utf-8-sig")),
        media_type="application/json",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.post("/import")
async def import_data(
    file: UploadFile = File(...),
    mode: str = "merge",
    conn: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    """导入 JSON 备份文件（仅管理员）。
    mode=merge: 合并导入（按食谱标题去重，跳过已存在）
    mode=replace: 先清空全部食谱/收藏/记录，再恢复
    """
    if not user["is_admin"]:
        raise HTTPException(status_code=403, detail="只有管理员可以导入数据")

    raw = await file.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="文件不是有效的 JSON 格式")

    if not isinstance(data, dict) or "recipes" not in data:
        raise HTTPException(status_code=400, detail="文件格式不正确，缺少 recipes 字段")

    admin_id = user["id"]
    imported_count = 0
    skipped_count = 0

    # 1) 恢复系统设置
    for k, v in (data.get("system_settings") or {}).items():
        conn.execute(
            "INSERT INTO system_settings(key,value,updated_at) VALUES(?,?,CURRENT_TIMESTAMP) "
            "ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=CURRENT_TIMESTAMP",
            (k, str(v)),
        )

    # 2) 恢复账号：按 username 合并（存在则更新资料、保留原密码；不存在则新建）
    user_id_map = {}
    for u in data.get("users", []):
        uname = (u.get("username") or "").strip()
        if not uname:
            continue
        old_id = u.get("id")
        row = conn.execute("SELECT id FROM users WHERE username = ?", (uname,)).fetchone()
        if row:
            new_id = row["id"]
            conn.execute(
                "UPDATE users SET display_name=?, avatar=?, is_admin=?, carousel_type=?, carousel_limit=? WHERE id=?",
                (u.get("display_name"), u.get("avatar"),
                 u.get("is_admin", 0), u.get("carousel_type", "most_cooked"),
                 u.get("carousel_limit", 10), new_id),
            )
        else:
            cur = conn.execute(
                "INSERT INTO users (username, display_name, avatar, password_hash, is_admin, carousel_type, carousel_limit) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (uname, u.get("display_name"), u.get("avatar"),
                 u.get("password_hash") or "", u.get("is_admin", 0),
                 u.get("carousel_type", "most_cooked"), u.get("carousel_limit", 10)),
            )
            new_id = cur.lastrowid
        if old_id is not None:
            user_id_map[old_id] = new_id

    # 3) replace 模式：清空全部食谱/收藏/记录（保留账号，避免把自己锁出去）
    if mode == "replace":
        conn.execute("DELETE FROM ingredients")
        conn.execute("DELETE FROM steps")
        conn.execute("DELETE FROM recipes")
        conn.execute("DELETE FROM favorites")
        conn.execute("DELETE FROM meals")
        conn.execute("DELETE FROM meal_plans")

    # 4) 恢复食谱（含食材/步骤），remap created_by 与 recipe id
    recipe_id_map = {}
    existing_titles = set()
    if mode == "merge":
        for r in conn.execute("SELECT title FROM recipes").fetchall():
            existing_titles.add(r["title"])

    for recipe in data.get("recipes", []):
        title = (recipe.get("title") or "").strip()
        if not title:
            continue
        if mode == "merge" and title in existing_titles:
            skipped_count += 1
            continue
        created_by = user_id_map.get(recipe.get("created_by"), admin_id)
        cur = conn.execute(
            """INSERT INTO recipes (title, description, category, meal_tags, servings,
                                    prep_time, cook_time, image_path, created_by)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (title, recipe.get("description"), recipe.get("category"),
             recipe.get("meal_tags"), recipe.get("servings", 2),
             recipe.get("prep_time"), recipe.get("cook_time"),
             recipe.get("image_path"), created_by),
        )
        new_rid = cur.lastrowid
        if recipe.get("id") is not None:
            recipe_id_map[recipe["id"]] = new_rid
        for ing in recipe.get("ingredients", []):
            conn.execute(
                "INSERT INTO ingredients (recipe_id, name, amount, unit) VALUES (?, ?, ?, ?)",
                (new_rid, ing.get("name", ""), ing.get("amount"), ing.get("unit")),
            )
        for step in recipe.get("steps", []):
            conn.execute(
                "INSERT INTO steps (recipe_id, step_number, description) VALUES (?, ?, ?)",
                (new_rid, step.get("step_number", 0), step.get("description", "")),
            )
        imported_count += 1
        if mode == "merge":
            existing_titles.add(title)

    def _uid(uid):
        return user_id_map.get(uid, admin_id)

    def _rid(rid):
        return recipe_id_map.get(rid, rid)

    # 5) 收藏 / 用餐记录 / 日历预定
    for fav in data.get("favorites", []):
        conn.execute(
            "INSERT OR IGNORE INTO favorites (user_id, recipe_id) VALUES (?, ?)",
            (_uid(fav.get("user_id")), _rid(fav.get("recipe_id"))),
        )
    for meal in data.get("meals", []):
        conn.execute(
            "INSERT INTO meals (user_id, recipe_id, meal_type, date) VALUES (?, ?, ?, ?)",
            (_uid(meal.get("user_id")), _rid(meal.get("recipe_id")),
             meal.get("meal_type", "dinner"), meal.get("date")),
        )
    for plan in data.get("meal_plans", []):
        conn.execute(
            "INSERT OR IGNORE INTO meal_plans (user_id, recipe_id, date, meal_type, is_planned) VALUES (?, ?, ?, ?, ?)",
            (_uid(plan.get("user_id")), _rid(plan.get("recipe_id")),
             plan.get("date"), plan.get("meal_type"), plan.get("is_planned", 1)),
        )

    conn.commit()
    return {
        "ok": True,
        "imported": imported_count,
        "skipped": skipped_count,
        "mode": mode,
    }
