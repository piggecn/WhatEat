"""系统设置路由 /api/system/*。"""
from typing import Optional
from urllib.request import urlopen, Request, ProxyHandler, build_opener, install_opener
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.auth import get_current_user, get_admin_user
from app.config import get_setting, set_setting, absolute_url
from app.database import get_db

router = APIRouter(prefix="/api/system", tags=["system"])


class SystemSettingsUpdate(BaseModel):
    public_base_url: Optional[str] = None
    site_name: Optional[str] = None
    pixabay_api_key: Optional[str] = None
    # —— 2026-08 新增字段 ——
    image_provider: Optional[str] = None     # pixabay | pixabay_zh | wikimedia
    proxy_url: Optional[str] = None          # 如 http://127.0.0.1:7890 ； 空=不使用
    proxy_test_url: Optional[str] = None     # 用来检测代理连通
    login_bg_image: Optional[str] = None     # 登录背景图地址
    # —— 食谱 API（无 Key）——
    recipe_source: Optional[str] = None      # themealdb
    recipe_translate: Optional[str] = None   # 1=英转中开 0=关
    # —— GitHub Releases 版本更新 ——
    github_repo: Optional[str] = None        # 形如 owner/repo


def _normalize_proxy(raw: str) -> str:
    raw = (raw or "").strip()
    if not raw:
        return ""
    # 去掉末尾斜杠，确保是 scheme://host[:port]
    raw = raw.rstrip("/")
    # 如果没写协议，默认 http
    if "://" not in raw:
        raw = "http://" + raw
    parsed = urlparse(raw)
    if parsed.scheme not in ("http", "https", "socks5", "socks5h"):
        raise ValueError("代理协议必须是 http / https / socks5 / socks5h")
    if not parsed.hostname:
        raise ValueError("代理地址缺少 host")
    return raw


def _try_proxy(proxy_url: str, target: str, timeout: int = 8) -> dict:
    """用给定代理请求 target，返回 ok/http_code/elapsed_ms 或 error。"""
    import time
    proxy = _normalize_proxy(proxy_url)
    parsed = urlparse(proxy)
    scheme = parsed.scheme
    proxy_host = f"{parsed.hostname}"
    if parsed.port:
        proxy_host += f":{parsed.port}"
    userinfo = ""
    if parsed.username:
        userinfo = parsed.username
        if parsed.password:
            userinfo += ":" + parsed.password
        userinfo += "@"
    handler = ProxyHandler({scheme: f"{scheme}://{userinfo}{proxy_host}"})
    opener = build_opener(handler)
    req = Request(target, headers={"User-Agent": "what-to-eat-today/1.0"})
    t0 = time.time()
    try:
        with opener.open(req, timeout=timeout) as resp:
            code = getattr(resp, "status", None) or resp.getcode() or 200
            body_preview = b""
            try:
                body_preview = resp.read(128)
            except Exception:
                pass
            return {
                "ok": True,
                "http_code": int(code),
                "elapsed_ms": int((time.time() - t0) * 1000),
                "target": target,
                "preview": body_preview.decode("utf-8", errors="ignore")[:32],
            }
    except Exception as e:
        return {
            "ok": False,
            "elapsed_ms": int((time.time() - t0) * 1000),
            "target": target,
            "error": f"{type(e).__name__}: {e}",
        }


@router.get("/settings")
def get_public_settings(conn=Depends(get_db)):
    """公开设置：前端初始化时读取；供关于页 / 移动端取服务器地址、版本等。"""
    return {
        "public_base_url": get_setting("public_base_url", conn=conn),
        "site_name": get_setting("site_name", "今天吃点啥", conn=conn),
        # 图片搜索当前使用的渠道（edit.html 用来渲染"去 XXX 官网找图"链接）
        "image_provider": get_setting("image_provider", "pixabay", conn=conn) or "pixabay",
        # 登录背景图：公开，供 login 页读取；若存储相对路径则统一转成绝对 URL
        "login_bg_image": absolute_url(get_setting("login_bg_image", "", conn=conn) or "") or "",
    }


@router.get("/settings/admin")
def get_admin_settings(conn=Depends(get_db), user=Depends(get_current_user)):
    """完整设置：仅管理员。"""
    if not user["is_admin"]:
        raise HTTPException(status_code=403, detail="仅管理员可查看系统设置")
    return {
        "public_base_url": get_setting("public_base_url", conn=conn),
        "site_name": get_setting("site_name", "今天吃点啥", conn=conn),
        "pixabay_api_key": get_setting("pixabay_api_key", "", conn=conn),
        "image_provider": get_setting("image_provider", "pixabay", conn=conn),
        "proxy_url": get_setting("proxy_url", "", conn=conn),
        "proxy_test_url": get_setting("proxy_test_url", "https://pixabay.com/api/docs/", conn=conn),
        "login_bg_image": get_setting("login_bg_image", "", conn=conn),
        "recipe_source": get_setting("recipe_source", "themealdb", conn=conn),
        "recipe_translate": get_setting("recipe_translate", "1", conn=conn),
    }


@router.put("/settings/admin")
def update_admin_settings(
    body: SystemSettingsUpdate,
    conn=Depends(get_db),
    user=Depends(get_current_user),
):
    """修改设置：仅管理员。"""
    if not user["is_admin"]:
        raise HTTPException(status_code=403, detail="仅管理员可修改系统设置")

    data = body.model_dump(exclude_unset=True)

    if "public_base_url" in data and data["public_base_url"] is not None:
        url = data["public_base_url"]
        if not (url.startswith("http://") or url.startswith("https://")):
            raise HTTPException(status_code=400, detail="public_base_url 必须以 http:// 或 https:// 开头")
        set_setting("public_base_url", url.rstrip("/"), conn=conn)

    if "site_name" in data and data["site_name"] is not None:
        set_setting("site_name", data["site_name"], conn=conn)

    if "pixabay_api_key" in data and data["pixabay_api_key"] is not None:
        set_setting("pixabay_api_key", data["pixabay_api_key"].strip(), conn=conn)

    if "image_provider" in data and data["image_provider"] is not None:
        prov = (data["image_provider"] or "").strip().lower()
        if prov and prov not in {"pixabay", "pixabay_zh", "wikimedia"}:
            raise HTTPException(status_code=400, detail="image_provider 必须是 pixabay / pixabay_zh / wikimedia 之一")
        set_setting("image_provider", prov or "pixabay", conn=conn)

    if "proxy_url" in data and data["proxy_url"] is not None:
        raw = (data["proxy_url"] or "").strip()
        if raw:
            try:
                _normalize_proxy(raw)
            except ValueError as e:
                raise HTTPException(status_code=400, detail=str(e))
        set_setting("proxy_url", _normalize_proxy(raw) if raw else "", conn=conn)

    if "proxy_test_url" in data and data["proxy_test_url"] is not None:
        t = (data["proxy_test_url"] or "").strip()
        if t and not (t.startswith("http://") or t.startswith("https://")):
            raise HTTPException(status_code=400, detail="proxy_test_url 必须 http(s) 开头")
        set_setting("proxy_test_url", t, conn=conn)

    if "login_bg_image" in data and data["login_bg_image"] is not None:
        set_setting("login_bg_image", (data["login_bg_image"] or "").strip(), conn=conn)

    if "recipe_source" in data and data["recipe_source"] is not None:
        src = (data["recipe_source"] or "").strip().lower()
        if src and src != "themealdb":
            raise HTTPException(status_code=400, detail="recipe_source 目前仅支持 themealdb")
        set_setting("recipe_source", src or "themealdb", conn=conn)

    if "recipe_translate" in data and data["recipe_translate"] is not None:
        v = "1" if str(data["recipe_translate"]) not in ("0", "", "false", "False") else "0"
        set_setting("recipe_translate", v, conn=conn)

    return {"ok": True}


@router.post("/update")
def trigger_update(user=Depends(get_admin_user)):
    """触发在线更新：拉取最新 Docker 镜像并重启服务。
    此接口仅管理员可调用，更新过程中服务会短暂中断。"""
    import subprocess
    import os
    try:
        # 执行 docker compose pull && up -d
        result = subprocess.run(
            ["docker", "compose", "pull", "--quiet"],
            capture_output=True,
            text=True,
            timeout=120,
        )
        if result.returncode != 0:
            raise RuntimeError(f"镜像拉取失败: {result.stderr}")

        result = subprocess.run(
            ["docker", "compose", "up", "-d", "--force-recreate"],
            capture_output=True,
            text=True,
            timeout=120,
        )
        if result.returncode != 0:
            raise RuntimeError(f"服务重启失败: {result.stderr}")

        return {"ok": True, "message": "更新成功，服务已重启"}
    except Exception as e:
        from fastapi import HTTPException
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/proxy/test")
def test_proxy(
    conn=Depends(get_db),
    user=Depends(get_current_user),
):
    """用当前 system_settings 里的 proxy_url 与 proxy_test_url 进行一次真实请求，
    返回结果（ok / http_code / elapsed_ms / error）。保证保存时能立刻验证代理可用。

    允许代理为空（此时直接连目标，作为"无代理也能通"的参照）。
    """
    if not user["is_admin"]:
        raise HTTPException(status_code=403, detail="仅管理员可测试代理")
    proxy = (get_setting("proxy_url", "", conn=conn) or "").strip()
    target = (get_setting("proxy_test_url", "https://pixabay.com/api/docs/", conn=conn) or "").strip()
    if not target:
        raise HTTPException(status_code=400, detail="proxy_test_url 未设置")
    try:
        if proxy:
            # 用代理请求
            return _try_proxy(proxy, target)
        # 无代理：直接连 target
        import time as _time
        req = Request(target, headers={"User-Agent": "what-to-eat-today/1.0"})
        t0 = _time.time()
        try:
            with urlopen(req, timeout=8) as resp:
                code = getattr(resp, "status", None) or resp.getcode() or 200
                return {"ok": True,
                        "http_code": int(code),
                        "elapsed_ms": int((_time.time() - t0) * 1000),
                        "target": target,
                        "proxy": "",
                        "note": "未使用代理"}
        except Exception as e:
            return {"ok": False,
                    "elapsed_ms": int((_time.time() - t0) * 1000),
                    "target": target,
                    "proxy": "",
                    "error": f"{type(e).__name__}: {e}",
                    "note": "未使用代理"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"{type(e).__name__}: {e}")
