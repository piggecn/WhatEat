"""应用运行日志：把关键请求/错误写入 app_logs 表，供前端日志弹窗查看。"""
import sqlite3
import threading
import time
import traceback
from datetime import datetime, timezone

_MAX_LOGS = 3000  # 保留最近 3000 条，超出自动清理
_LOCK = threading.Lock()


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _get_conn():
    from app.database import DATABASE_PATH
    conn = sqlite3.connect(DATABASE_PATH, check_same_thread=False, isolation_level=None)
    conn.row_factory = sqlite3.Row
    return conn


def _prune_if_needed(conn):
    try:
        n = conn.execute("SELECT COUNT(*) FROM app_logs").fetchone()[0]
    except sqlite3.OperationalError:
        return
    if n > _MAX_LOGS + 500:
        cut = n - _MAX_LOGS
        conn.execute(f"DELETE FROM app_logs WHERE id <= (SELECT id FROM app_logs ORDER BY id LIMIT 1 OFFSET {cut})")
        conn.commit()


def log(level: str, category: str, summary: str, detail=None):
    """把一条日志写入 app_logs 表。异常场景直接 catch，绝不抛错。"""
    if level not in ("INFO", "WARN", "ERROR"):
        level = "INFO"
    try:
        with _LOCK:
            conn = _get_conn()
            try:
                conn.execute(
                    "INSERT INTO app_logs(ts, level, category, summary, detail) VALUES(?,?,?,?,?)",
                    (_now_iso(), level, category, summary, detail),
                )
                _prune_if_needed(conn)
            finally:
                try:
                    conn.close()
                except Exception:
                    pass
    except Exception:
        pass


def log_error(category: str, summary: str, exc: BaseException = None):
    detail = None
    if exc is not None:
        detail = f"{type(exc).__name__}: {exc}\n{traceback.format_exc(limit=3)}"
    log("ERROR", category, summary, detail)


def log_request(method: str, path: str, status: int, elapsed_ms: int, user_id=None, detail=None):
    if status >= 500:
        log("ERROR", "request", f"{method} {path} -> {status}", detail or f"elapsed={elapsed_ms}ms, user={user_id}")
    elif status >= 400:
        log("WARN", "request", f"{method} {path} -> {status}", detail or f"elapsed={elapsed_ms}ms, user={user_id}")
    elif status in (401, 403):
        log("WARN", "auth", f"{method} {path} -> {status}", detail or f"user={user_id}")
    else:
        return


def get_logs(limit: int = 100) -> list[dict]:
    conn = _get_conn()
    try:
        rows = conn.execute(
            "SELECT id, ts, level, category, summary, detail, created_at "
            "FROM app_logs ORDER BY id DESC LIMIT ?",
            (min(int(limit), 500),),
        ).fetchall()
        out = [dict(r) for r in rows]
        out.reverse()
        return out
    except sqlite3.OperationalError:
        return []
    finally:
        try:
            conn.close()
        except Exception:
            pass


def clear_logs():
    try:
        with _LOCK:
            conn = _get_conn()
            conn.execute("DELETE FROM app_logs")
            conn.commit()
    except Exception:
        pass
