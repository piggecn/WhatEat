"""应用发布信息路由 /api/app/*。

APK 联动：通过 GitHub Releases 公开 API 拉取最新版本信息，
供 APK 启动时做「版本检测 / 强制更新」、网页「关于」页展示。
无需 Key（公开仓库 60 次/小时/IP，另有 30 分钟缓存）。
"""
import json
import os
import time
import urllib.request
from typing import Optional

import sqlite3
from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from app.config import get_setting, APP_VERSION
from app.database import get_db
from app.routes.search_image import _make_http_opener
from app.auth import get_current_user
import app.app_logger as app_log

router = APIRouter(prefix="/api/app", tags=["app"])

_GH_ENDPOINT = "https://api.github.com/repos/{repo}/releases/latest"
_CACHE: dict = {"ts": 0.0, "data": None}


def _md_to_html(text: str) -> str:
    """把 GitHub Release 的 Markdown 正文转成安全的内联 HTML（先转义再渲染）。"""
    import html as _html
    out = []
    in_list = False
    for raw in (text or "").splitlines():
        line = raw.rstrip()
        if not line.strip():
            if in_list:
                out.append("</ul>")
                in_list = False
            continue
        esc = _html.escape(line)
        if line.startswith("## "):
            if in_list:
                out.append("</ul>")
                in_list = False
            out.append(f'<h3 class="font-medium text-foreground mt-3 mb-1">{esc[3:]}</h3>')
        elif line.startswith("# "):
            out.append(f'<h2 class="font-semibold text-foreground mt-3 mb-1">{esc[2:]}</h2>')
        elif line.strip().startswith("- "):
            if not in_list:
                out.append('<ul class="list-disc pl-5 space-y-1">')
                in_list = True
            out.append(f"<li>{esc[line.find('-') + 2:]}</li>")
        else:
            if in_list:
                out.append("</ul>")
                in_list = False
            out.append(f"<p>{esc}</p>")
    if in_list:
        out.append("</ul>")
    return "".join(out)
_CACHE_TTL = 1800  # 30 分钟
_security = HTTPBearer(auto_error=False)

# 发布仓库：硬编码为当前项目的 GitHub 仓库地址
_GITHUB_REPO = os.getenv("GITHUB_REPO", "piggecn/WhatEat")


def _fetch_github(repo: str, proxy_url: str = "") -> dict:
    url = _GH_ENDPOINT.format(repo=repo)
    headers = {
        "User-Agent": "what-to-eat-today/1.0",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    req = urllib.request.Request(url, headers=headers)
    opener = _make_http_opener(proxy_url)
    if opener is None:
        with urllib.request.urlopen(req, timeout=12) as resp:
            return json.loads(resp.read().decode("utf-8"))
    with opener.open(req, timeout=12) as resp:
        return json.loads(resp.read().decode("utf-8"))


@router.get("/check")
def app_check(force: bool = False, conn: sqlite3.Connection = Depends(get_db)):
    """最新版本信息（公开接口，APK 免登录调用）。同时返回服务器自身版本供版本比对。
    force=true 时跳过缓存，立即向 GitHub 重新拉取（用于「检测更新」按钮）。"""
    now = time.time()
    if not force and _CACHE["data"] is not None and now - _CACHE["ts"] < _CACHE_TTL:
        return _CACHE["data"]

    # 服务器版本：优先用代码内置版本
    server_version = APP_VERSION
    if not server_version.startswith("v"):
        server_version = "v" + server_version

    repo = _GITHUB_REPO
    proxy_url = (get_setting("proxy_url", "", conn=conn) or "").strip()

    try:
        d = _fetch_github(repo, proxy_url)
        if "message" in d and "tag_name" not in d:
            raise RuntimeError(str(d.get("message") or "GitHub API 错误"))
        assets = [
            {"name": a.get("name"), "url": a.get("browser_download_url")}
            for a in (d.get("assets") or [])
            if a.get("browser_download_url")
        ]
        result = {
            "configured": True,
            "repo": repo,
            "server_version": server_version,
            "version": (d.get("tag_name") or "").lstrip("v"),
            "name": d.get("name") or "",
            "notes": d.get("body") or "",
            "notes_html": _md_to_html(d.get("body") or ""),
            "published_at": d.get("published_at") or "",
            "pre_release": bool(d.get("prerelease")),
            "assets": assets,
        }
    except Exception as e:
        result = {
            "configured": True,
            "repo": repo,
            "server_version": server_version,
            "error": f"{type(e).__name__}: {e}",
        }
    _CACHE.update(ts=now, data=result)
    return result


@router.get("/logs")
def get_logs(limit: int = 100, user=Depends(get_current_user)):
    """读取应用运行日志：仅管理员可查看（前端用户菜单「日志」入口）。"""
    if not user["is_admin"]:
        raise HTTPException(status_code=403, detail="仅管理员可查看日志")
    try:
        out = app_log.get_logs(int(limit))
        return {"logs": out, "total": len(out)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/logs")
def clear_logs(user=Depends(get_current_user)):
    """清空应用运行日志：仅管理员可操作。"""
    if not user["is_admin"]:
        raise HTTPException(status_code=403, detail="仅管理员可清空日志")
    try:
        app_log.clear_logs()
        return {"ok": True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))