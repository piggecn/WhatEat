"""SQLite 数据库连接、建表与初始化。"""
import os
import sqlite3
from typing import Iterator

DATABASE_PATH = os.getenv("DATABASE_PATH", "/app/data/recipes.db")
UPLOAD_DIR = os.getenv("UPLOAD_DIR", "/app/data/uploads")


def get_db() -> Iterator[sqlite3.Connection]:
    """FastAPI 依赖：每请求一个连接，开启外键约束，请求结束关闭。"""
    conn = sqlite3.connect(DATABASE_PATH, check_same_thread=False, isolation_level=None)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        yield conn
    finally:
        conn.close()


SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    username        TEXT UNIQUE NOT NULL,
    display_name    TEXT,
    avatar          TEXT,
    password_hash   TEXT NOT NULL,
    is_admin        INTEGER DEFAULT 0,
    carousel_type   TEXT DEFAULT 'most_cooked',
    carousel_limit  INTEGER DEFAULT 10,
    avoid_tags      TEXT,
    created_at      TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS recipes (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    title       TEXT NOT NULL,
    description TEXT,
    category    TEXT,
    meal_tags   TEXT,
    diet_tags   TEXT,
    servings    INTEGER DEFAULT 2,
    prep_time   INTEGER,
    cook_time   INTEGER,
    image_path  TEXT,
    created_by  INTEGER REFERENCES users(id),
    created_at  TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at  TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ingredients (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    recipe_id INTEGER REFERENCES recipes(id) ON DELETE CASCADE,
    name      TEXT NOT NULL,
    amount    TEXT,
    unit      TEXT
);

CREATE TABLE IF NOT EXISTS steps (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    recipe_id   INTEGER REFERENCES recipes(id) ON DELETE CASCADE,
    step_number INTEGER NOT NULL,
    description TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS favorites (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id   INTEGER REFERENCES users(id) ON DELETE CASCADE,
    recipe_id INTEGER REFERENCES recipes(id) ON DELETE CASCADE,
    UNIQUE(user_id, recipe_id)
);

CREATE TABLE IF NOT EXISTS meals (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id    INTEGER REFERENCES users(id) ON DELETE CASCADE,
    recipe_id  INTEGER REFERENCES recipes(id) ON DELETE CASCADE,
    meal_type  TEXT DEFAULT 'dinner',  -- breakfast/lunch/dinner
    date       TEXT NOT NULL,           -- YYYY-MM-DD
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS meal_plans (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id    INTEGER REFERENCES users(id) ON DELETE CASCADE,
    recipe_id  INTEGER REFERENCES recipes(id) ON DELETE CASCADE,
    date       TEXT NOT NULL,           -- YYYY-MM-DD
    meal_type  TEXT NOT NULL,           -- breakfast/lunch/dinner
    is_planned INTEGER DEFAULT 1,       -- 1=预定 0=已完成
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS translations (
    key        TEXT PRIMARY KEY,        -- sha1(source + text + langpair) 缓存命中用
    langpair   TEXT NOT NULL,           -- en|zh-CN
    source     TEXT,                    -- 来自哪个服务（dict / mymemory）
    result     TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
"""


def _column_exists(conn, table: str, column: str) -> bool:
    """判断列是否已存在（用于 ALTER TABLE 迁移）。"""
    cols = [r[1] for r in conn.execute(f"PRAGMA table_info({table})").fetchall()]
    return column in cols


def init_db() -> None:
    """建表并初始化 admin 用户。幂等。含增量迁移。"""
    os.makedirs(os.path.dirname(DATABASE_PATH), exist_ok=True)
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    conn.executescript(SCHEMA)
    conn.commit()

    # ---- users 表迁移 ----
    if not _column_exists(conn, "users", "display_name"):
        conn.execute("ALTER TABLE users ADD COLUMN display_name TEXT")
        conn.commit()
    if not _column_exists(conn, "users", "avatar"):
        conn.execute("ALTER TABLE users ADD COLUMN avatar TEXT")
        conn.commit()
    if not _column_exists(conn, "users", "carousel_type"):
        conn.execute("ALTER TABLE users ADD COLUMN carousel_type TEXT DEFAULT 'most_cooked'")
        conn.commit()
    if not _column_exists(conn, "users", "carousel_limit"):
        conn.execute("ALTER TABLE users ADD COLUMN carousel_limit INTEGER DEFAULT 10")
        conn.commit()
    # 兼容旧库：display_name 默认填 username
    conn.execute(
        "UPDATE users SET display_name = username WHERE display_name IS NULL OR display_name = ''"
    )
    # 兼容旧库：avatar 从旧的 avatar_path 同步（不删 avatar_path 保持兼容）
    if _column_exists(conn, "users", "avatar_path"):
        conn.execute(
            "UPDATE users SET avatar = avatar_path WHERE (avatar IS NULL OR avatar = '') AND avatar_path IS NOT NULL"
        )
    conn.commit()

    # 迁移：为 users 增加 avatar_path 列（旧库兼容，保留）
    if not _column_exists(conn, "users", "avatar_path"):
        conn.execute("ALTER TABLE users ADD COLUMN avatar_path TEXT")
        conn.commit()

    # ---- recipes 表迁移 ----
    if not _column_exists(conn, "recipes", "meal_tags"):
        conn.execute("ALTER TABLE recipes ADD COLUMN meal_tags TEXT")
        conn.commit()
    if not _column_exists(conn, "recipes", "diet_tags"):
        conn.execute("ALTER TABLE recipes ADD COLUMN diet_tags TEXT")
        conn.commit()
    if not _column_exists(conn, "users", "avoid_tags"):
        conn.execute("ALTER TABLE users ADD COLUMN avoid_tags TEXT")
        conn.commit()
    # meal_tags 数据迁移：根据 category 推导默认值
    for row in conn.execute(
        "SELECT id, category FROM recipes WHERE meal_tags IS NULL OR meal_tags = ''"
    ).fetchall():
        cat = row["category"]
        tags = []
        if cat == "早餐":
            tags = ["breakfast"]
        elif cat == "午餐":
            tags = ["lunch"]
        elif cat == "晚餐":
            tags = ["dinner"]
        elif cat in ("甜点", "小吃"):
            tags = ["lunch", "dinner"]
        elif cat == "饮品":
            tags = ["breakfast", "lunch", "dinner"]
        if tags:
            import json as _json
            conn.execute(
                "UPDATE recipes SET meal_tags = ? WHERE id = ?",
                (_json.dumps(tags, ensure_ascii=False), row["id"]),
            )
    conn.commit()

    # ---- meal_plans 迁移：去掉 UNIQUE(user_id,date,meal_type)，支持每餐多道菜 ----
    try:
        sql = conn.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='meal_plans'").fetchone()
        if sql and "UNIQUE" in (sql["sql"] or "").upper():
            conn.executescript(
                "CREATE TABLE meal_plans_new ("
                "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                "user_id INTEGER REFERENCES users(id) ON DELETE CASCADE, "
                "recipe_id INTEGER REFERENCES recipes(id) ON DELETE CASCADE, "
                "date TEXT NOT NULL, "
                "meal_type TEXT NOT NULL, "
                "is_planned INTEGER DEFAULT 1, "
                "created_at TEXT DEFAULT CURRENT_TIMESTAMP);"
                "INSERT INTO meal_plans_new (id,user_id,recipe_id,date,meal_type,is_planned,created_at) "
                "SELECT id,user_id,recipe_id,date,meal_type,is_planned,created_at FROM meal_plans;"
                "DROP TABLE meal_plans;"
                "ALTER TABLE meal_plans_new RENAME TO meal_plans;"
            )
            conn.commit()
    except Exception:
        pass

    # ---- system_settings 表 ----
    conn.execute(
        "CREATE TABLE IF NOT EXISTS system_settings ("
        "key TEXT PRIMARY KEY, "
        "value TEXT NOT NULL, "
        "updated_at TEXT DEFAULT CURRENT_TIMESTAMP)"
    )
    conn.commit()
    default_url = os.getenv('PUBLIC_BASE_URL', 'http://localhost:8765').rstrip('/')
    conn.executemany(
        "INSERT OR IGNORE INTO system_settings(key, value) VALUES(?, ?)",
        [
            ('public_base_url', default_url),
            ('site_name', '今天吃点啥'),
            ('pixabay_api_key', ''),
            # —— 2026-08 新增：多图片来源渠道 / 代理 / 登录背景图 ——
            ('image_provider', 'pixabay'),      # pixabay | pixabay_zh | wikimedia
            ('proxy_url', ''),                   # 例如 http://127.0.0.1:7890
            ('proxy_test_url', 'https://pixabay.com/api/docs/'),  # 用来测代理连通的目标
            ('login_bg_image', ''),              # 封面图 url / 上传路径
            # —— 2026-09 新增：食谱 API（无 Key 方案）——
            ('recipe_source', 'themealdb'),      # 食谱数据源：themealdb（无需 Key）
            ('recipe_translate', '1'),           # 英转中开关：1=开 0=关
            # —— 2026-09 新增：GitHub Releases 版本更新 ——
            ('github_repo', ''),                 # 形如 owner/repo（Android 发版仓库）
            # —— 2026-09 新增：服务器自身版本（后台可更新，方便与客户端版本比对） ——
            ('server_version', ''),              # 例：v0.0.2；留空=用代码内置 APP_VERSION
        ],
    )
    conn.commit()

    # ---- app_logs 表迁移（增量） ----
    try:
        cur = conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='app_logs'").fetchone()
        if cur is None:
            conn.execute(
                "CREATE TABLE IF NOT EXISTS app_logs ("
                "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                "ts TEXT NOT NULL, "
                "level TEXT NOT NULL, "
                "category TEXT NOT NULL, "
                "summary TEXT NOT NULL, "
                "detail TEXT, "
                "created_at TEXT DEFAULT CURRENT_TIMESTAMP)"
            )
            conn.commit()
    except sqlite3.OperationalError:
        pass

    # 初始化 admin
    cur = conn.execute("SELECT id FROM users WHERE username = ?", ("admin",))
    if cur.fetchone() is None:
        from app.auth import hash_password
        conn.execute(
            "INSERT INTO users (username, display_name, password_hash, is_admin) VALUES (?, ?, ?, 1)",
            ("admin", "管理员", hash_password("admin123")),
        )
        conn.commit()
    conn.close()
