"""系统配置 + 绝对 URL 工具。"""
import os
import sqlite3
from typing import Optional
from app.database import get_db  # same generator; use next(get_db()) pattern

ENV_PUBLIC_BASE_URL = os.getenv('PUBLIC_BASE_URL', 'http://localhost:8765').rstrip('/')

APP_VERSION = "0.0.1"


def _safe_connect():
    """临时独立连接：对 sqlite3.Row + row_factory + autocommit，用完即关。
    避免复用请求连接被关闭后抛出 'Cannot operate on a closed database'。"""
    from app.database import DATABASE_PATH
    conn = sqlite3.connect(DATABASE_PATH, check_same_thread=False, isolation_level=None)
    conn.row_factory = sqlite3.Row
    return conn


def get_setting(key: str, default: Optional[str] = None, conn=None) -> Optional[str]:
    """读 system_settings，无值则 fallback 到环境变量（只对已知的 key 做 env fallback）。

    优先复用调用方传入的 db 连接；否则临时创建一个独立连接（即开即关）。
    """
    env_fallback = {
        'public_base_url': ENV_PUBLIC_BASE_URL,
        'site_name': os.getenv('SITE_NAME', '今天吃点啥'),
    }
    local = conn
    created = False
    try:
        if local is None:
            # 不使用 get_db() 生成器：其 finally 块会在 yield 后被 GC 触发 close，
            # 在非请求上下文（启动期 / 中间件）里容易复现 closed db 错误。
            local = _safe_connect()
            created = True
        row = local.execute("SELECT value FROM system_settings WHERE key = ?", (key,)).fetchone()
        if row is not None:
            return row["value"]
    except sqlite3.OperationalError as e:
        # system_settings 表尚未初始化（init_db 还没跑）时静默返回 fallback
        if "no such table" not in str(e).lower():
            import traceback
            traceback.print_exc()
    except Exception:
        import traceback
        traceback.print_exc()
    finally:
        if created and local is not None:
            try:
                local.close()
            except Exception:
                pass
    return env_fallback.get(key, default)


def set_setting(key: str, value: str, conn=None) -> None:
    """写入 system_settings。优先复用调用方传入的 db 连接（避免 generator 提前关闭）。"""
    local_conn = conn
    created = False
    if local_conn is None:
        local_conn = _safe_connect()
        created = True
    try:
        local_conn.execute(
            "INSERT INTO system_settings(key, value, updated_at) VALUES(?,?,CURRENT_TIMESTAMP) "
            "ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=CURRENT_TIMESTAMP",
            (key, str(value)),
        )
        local_conn.commit()
    finally:
        if created:
            try:
                local_conn.close()
            except Exception:
                pass


def public_base_url() -> str:
    return (get_setting('public_base_url') or ENV_PUBLIC_BASE_URL).rstrip('/')


def absolute_url(path: Optional[str]) -> Optional[str]:
    if path is None:
        return None
    if isinstance(path, str) and path.startswith(('http://', 'https://', 'data:')):
        return path
    base = public_base_url()
    if path.startswith('/'):
        return base + path
    return base + '/' + path
