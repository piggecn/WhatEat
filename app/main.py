"""FastAPI 应用入口。"""
import os
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse
from fastapi.staticfiles import StaticFiles
from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware
import os as _os
from app import config as _cfg

from app import pages
from app.database import init_db, UPLOAD_DIR
from app.routes import auth as auth_routes
from app.routes import app as app_routes
from app.routes import calendar as calendar_routes
from app.routes import carousel as carousel_routes
from app.routes import data as data_routes
from app.routes import meals as meal_routes
from app.routes import profile as profile_routes
from app.routes import random as random_routes
from app.routes import recipes as recipe_routes
from app.routes import recipe_api as recipe_api_routes
from app.routes import search_image as search_image_routes
from app.routes import system as system_routes
from app.routes import upload as upload_routes
from app.routes import users as user_routes

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
STATIC_DIR = os.path.join(BASE_DIR, "..", "static")


@asynccontextmanager
async def lifespan(app: FastAPI):
    os.makedirs(UPLOAD_DIR, exist_ok=True)
    os.makedirs(STATIC_DIR, exist_ok=True)
    init_db()
    yield


app = FastAPI(title="今天吃点啥", lifespan=lifespan)

# 反代头：让 FastAPI 感知 X-Forwarded-Proto（HTTPS）/ Host
app.add_middleware(ProxyHeadersMiddleware, trusted_hosts="*")
# CORS：Web 端域名白名单（Native Android 不需要 CORS）
_cors_origins = [
    _cfg.public_base_url(),                            # 反代 HTTPS 地址
    "http://localhost:8765",                            # 本机直连
    "http://127.0.0.1:8765",
    "capacitor://localhost",                             # Capacitor WebView
    "http://localhost",                                   # 本地开发
]
# 从 env 里接收额外允许的来源（逗号分隔），适合多域名场景
_extra = _os.getenv("CORS_ORIGINS", "")
if _extra:
    _cors_origins.extend([o.strip() for o in _extra.split(",") if o.strip()])
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 头像渲染辅助函数：根据 avatar 字段值决定渲染方式
# avatar 可能是：上传路径（/uploads/xxx.jpg）、预设 key（dad/mom/...）、或空
PRESET_EMOJI = {
    "dad": "👨", "mom": "👩", "grandpa": "👴", "grandma": "👵",
    "brother": "🧑", "sister": "👧", "little_brother": "👦", "little_sister": "🧒",
    "son": "👶", "daughter": "👧",
}
DISPLAY_EMOJI = {
    "爸爸": "👨", "妈妈": "👩", "爷爷": "👴", "奶奶": "👵",
    "哥哥": "🧑", "姐姐": "👧", "弟弟": "👦", "妹妹": "🧒",
    "儿子": "👶", "女儿": "👧",
}


def avatar_html(avatar=None, display_name="", username="", size=32):
    """根据 avatar 字段值返回头像 HTML。
    - 上传路径（/uploads/xxx）→ <img>
    - 预设 key（dad/mom/...）→ emoji <span>
    - 都没有 → dicebear 默认头像
    """
    cls = f"w-{size//4} h-{size//4} rounded-full border border-border bg-card object-cover"
    if avatar and (avatar.startswith("/") or avatar.startswith("http")):
        return f'<img src="{avatar}" class="{cls}">'
    if avatar and avatar in PRESET_EMOJI:
        return f'<span class="inline-flex items-center justify-center {cls} text-lg">{PRESET_EMOJI[avatar]}</span>'
    if display_name and display_name in DISPLAY_EMOJI:
        return f'<span class="inline-flex items-center justify-center {cls} text-lg">{DISPLAY_EMOJI[display_name]}</span>'
    seed = username or display_name or "user"
    return f'<img src="https://api.dicebear.com/7.x/avataaars/svg?seed={seed}" class="{cls}">'


# 注册为 Jinja2 全局函数
pages.templates.env.globals["avatar_html"] = avatar_html
# 注入版本号
from app.config import APP_VERSION as _APP_VERSION
pages.templates.env.globals["APP_VERSION"] = _APP_VERSION


# 防止浏览器缓存 HTML/JS（前端迭代后避免用户拿旧版导致跳转循环）
@app.middleware("http")
async def no_cache_html(request, call_next):
    response = await call_next(request)
    ct = response.headers.get("content-type", "")
    if "text/html" in ct or "javascript" in ct:
        response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
        response.headers["Pragma"] = "no-cache"
        response.headers["Expires"] = "0"
    return response


# 应用运行日志：仅记录关键事件（5xx/4xx/认证失败），跳过静态资源与公开页，写入 app_logs 表
# 通过 request.scope 拿到当前登录 user（如果已经识别过）
import app.app_logger as _app_log

def _extract_user_from_scope(scope: dict):
    try:
        return scope.get("current_user_id")
    except Exception:
        return None


@app.middleware("http")
async def logging_middleware(request, call_next):
    path = request.url.path
    # 忽略静态资源 / favicon / vite hmr stub
    if path.startswith(("/static/", "/favicon.ico", "/@vite")):
        return await call_next(request)
    if path.startswith("/docs") or path.startswith("/openapi"):
        return await call_next(request)
    try:
        t0 = time.monotonic()
        resp = await call_next(request)
        elapsed = int((time.monotonic() - t0) * 1000)
        user_id = _extract_user_from_scope(request.scope)
        _app_log.log_request(request.method, path, resp.status_code, elapsed, user_id)
        return resp
    except Exception as e:
        _app_log.log_error("request", f"{request.method} {path} raised {type(e).__name__}: {e}")
        raise


# 兜底：@tailwindcss/browser CDN v4 会尝试请求 /@vite/client 做 HMR 探测，
# 这个路径不存在会在每个页面产生 404。这里返回空脚本消除网络面板报错。
@app.get("/@vite/client", include_in_schema=False)
async def vite_client_stub():
    return PlainTextResponse("// vite hmr client stub (noop)\n", media_type="application/javascript")


# 路由
app.include_router(auth_routes.router)
app.include_router(app_routes.router)
# random 前缀也是 /api/recipes，但路径是 /random，必须先于 recipes 的 /{recipe_id} 注册才能优先匹配
app.include_router(random_routes.router)
# carousel 前缀也是 /api/recipes，路径是 /carousel，同样先注册
app.include_router(carousel_routes.router)
app.include_router(recipe_routes.router)
app.include_router(user_routes.router)
app.include_router(upload_routes.router)
app.include_router(meal_routes.router)
app.include_router(calendar_routes.router)
app.include_router(profile_routes.router)
app.include_router(system_routes.router)
app.include_router(data_routes.router)
app.include_router(recipe_api_routes.router)
app.include_router(search_image_routes.router)
app.include_router(pages.router)

# 静态资源（挂载前确保目录存在，StaticFiles 构造即检查）
os.makedirs(UPLOAD_DIR, exist_ok=True)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")
