# -*- coding: utf-8 -*-
"""生成离线菜谱索引：app/recipe_index.json

整合两个免 Key 数据源的全量数据，打包进镜像后搜索零外网依赖：
  1. TheMealDB：按首字母 a-z 拉全量（~300 道，测试 Key "1" 即可）
  2. HowToCook：README 索引 + 逐个拉取菜谱 Markdown（~390 道）

用法（在源码根目录，需已安装 requirements）：
  python scripts/build_recipe_index.py [--proxy http://127.0.0.1:7892]
"""
import argparse
import io
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.routes.recipe_api import (  # noqa: E402
    _htc_fetch, _htc_index, _normalize_meal, _parse_htc_recipe,
    _HTC_CATEGORY_MAP, HOWTOCOOK_BASES,
)
from app.routes.search_image import _make_http_opener  # noqa: E402

UA = {"User-Agent": "what-to-eat-today/1.0", "Accept": "application/json"}
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "app", "recipe_index.json")


def fetch_json(url, proxy):
    req = urllib.request.Request(url, headers=UA)
    opener = _make_http_opener(proxy) or urllib.request.build_opener()
    with opener.open(req, timeout=20) as r:
        return json.loads(r.read().decode("utf-8"))


def build_themealdb(proxy):
    """按首字母枚举 TheMealDB 全量菜谱。"""
    seen = {}
    for letter in "abcdefghijklmnopqrstuvwxyz":
        try:
            data = fetch_json(f"https://www.themealdb.com/api/json/v1/1/search.php?f={letter}", proxy)
        except Exception as e:
            print(f"[themealdb] letter {letter} FAIL {type(e).__name__}: {e}", flush=True)
            continue
        for m in (data.get("meals") or []):
            mid = str(m.get("idMeal") or "")
            if mid and mid not in seen:
                seen[mid] = _normalize_meal(m)
        time.sleep(0.2)
    print(f"[themealdb] total {len(seen)}", flush=True)
    return list(seen.values())


def build_howtocook(proxy):
    """按 README 索引拉取全部 HowToCook 菜谱 Markdown 并解析。"""
    dishes = _htc_index(proxy)
    if not dishes:
        print("[howtocook] index EMPTY", flush=True)
        return []
    out = []
    fail = 0
    for i, d in enumerate(dishes, 1):
        path_q = "/".join(urllib.parse.quote(seg) for seg in d["path"].split("/"))
        md = None
        for base in HOWTOCOOK_BASES:
            try:
                md = _htc_fetch(f"{base}/{path_q}", proxy)
                if md:
                    break
            except Exception:
                continue
        if not md:
            fail += 1
            print(f"[howtocook] FAIL {d['title']}", flush=True)
            continue
        parsed = _parse_htc_recipe(md)
        out.append({
            "id": d["path"],
            "title": parsed.get("title") or d["title"],
            "category": _HTC_CATEGORY_MAP.get(d["category"], "晚餐"),
            "raw_category": d["category"],
            "area": "HowToCook 中文菜谱库",
            "thumb": "",
            "ingredients": parsed.get("ingredients") or [],
            "steps": parsed.get("steps") or [],
            "source": "howtocook",
        })
        if i % 50 == 0:
            print(f"[howtocook] {i}/{len(dishes)}", flush=True)
        time.sleep(0.15)
    print(f"[howtocook] total {len(out)} fail {fail}", flush=True)
    return out


_WIKILINK = re.compile(r"\[\[[^\]|]*(?:\|([^\]]+))?\]\]")


def _clean_wiki(s: str) -> str:
    return _WIKILINK.sub(lambda m: (m.group(1) or m.group(0)).strip(), s).replace(":", "").strip()


def _wikitext_to_recipe(wikitext: str) -> dict:
    """zh.wikibooks 食谱页 wikitext → {title, ingredients, steps}。
    兼容三种常见格式：
      A. ===材料=== 主料/辅料行 + ====做法==== 编号行（1、2、）
      B. ==做法== #列表行（无食材节）
      C. ==原料== *名称 数量单位 行 + ==做法== #列表行
    """
    title = ""
    m = re.search(r"^'''(.+?)'''", wikitext)
    if m:
        title = m.group(1).strip()
    lines = [ln.strip() for ln in wikitext.splitlines()]
    section = ""
    ingredients = []
    steps = []
    for ln in lines:
        hm = re.match(r"^=+\s*(.+?)\s*=+$", ln)
        if hm:
            section = hm.group(1).strip()
            continue
        if section in ("材料", "用料", "食材", "原料"):
            if ln.startswith("*"):
                item = _clean_wiki(ln[1:].strip())
                if not item:
                    continue
                m2 = re.match(r"^(.+?)\s+([\d.]+(?:[-~][\d.]+)?)\s*(克|g|kg|毫升|ml|个|只|根|片|斤|两|汤匙|茶匙|勺|杯)\s*$", item)
                if m2:
                    ingredients.append({"name": m2.group(1).strip(), "amount": m2.group(2), "unit": m2.group(3)})
                else:
                    ingredients.append({"name": item, "amount": "", "unit": ""})
            elif "：" in ln or ":" in ln:
                for part in re.split(r"[；;，、]", ln):
                    part = re.sub(r"^(主料|辅料|配料|调料)[：:]", "", part).strip()
                    part = _clean_wiki(part)
                    if part and not part.startswith(("主料", "辅料", "配料", "调料")):
                        ingredients.append({"name": part, "amount": "", "unit": ""})
        elif section in ("做法", "操作", "製作方法", "制作方法"):
            m2 = re.match(r"^#+\s*(.+)$", ln)
            if m2:
                s = _clean_wiki(m2.group(1))
                if s:
                    steps.append(s)
                continue
            m2 = re.match(r"^\d+[、.．)）]\s*(.+)$", ln)
            if m2:
                s = _clean_wiki(m2.group(1))
                if s:
                    steps.append(s)
    if not steps:
        # 兜底：全篇 # 列表行
        for ln in lines:
            m2 = re.match(r"^#+\s*(.+)$", ln)
            if m2 and not ln.startswith("#REDIRECT") and not ln.startswith("#重定向"):
                s = _clean_wiki(m2.group(1))
                if s and not s.startswith("[["):
                    steps.append(s)
    return {"title": title, "ingredients": ingredients, "steps": steps}


def build_wikibooks(proxy):
    """拉取 zh.wikibooks Category:食谱 全部成员并解析（CC BY-SA 自由内容）。"""
    API = "https://zh.wikibooks.org/w/api.php"
    opener = _make_http_opener(proxy) or urllib.request.build_opener()

    def api(params):
        url = API + "?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, headers=UA)
        with opener.open(req, timeout=25) as r:
            return json.loads(r.read().decode("utf-8"))

    members = []
    cmcontinue = None
    while True:
        params = {"action": "query", "format": "json", "list": "categorymembers",
                  "cmtitle": "Category:食譜", "cmlimit": 500}
        if cmcontinue:
            params["cmcontinue"] = cmcontinue
        d = api(params)
        members += [x["title"] for x in d.get("query", {}).get("categorymembers", [])
                    if not x["title"].startswith(("Category:", "食谱/参考", "食譜/参考"))]
        cmcontinue = (d.get("continue") or {}).get("cmcontinue")
        if not cmcontinue:
            break
    print(f"[wikibooks] members {len(members)}", flush=True)

    out = []
    for i in range(0, len(members), 50):
        batch = members[i:i + 50]
        try:
            d = api({"action": "query", "format": "json", "prop": "revisions",
                     "rvprop": "content", "rvslots": "main", "titles": "|".join(batch)})
        except Exception as e:
            print(f"[wikibooks] batch FAIL {type(e).__name__}: {e}", flush=True)
            continue
        for page in (d.get("query", {}).get("pages", {}) or {}).values():
            revs = page.get("revisions") or []
            if not revs:
                continue
            wt = (revs[0].get("slots") or {}).get("main", {}).get("*") or ""
            parsed = _wikitext_to_recipe(wt)
            if not parsed["ingredients"] and not parsed["steps"]:
                continue
            out.append({
                "id": page.get("title", ""),
                "title": parsed["title"] or page.get("title", "").replace("食谱/", "").replace("食譜/", ""),
                "category": "晚餐",
                "raw_category": "维基食谱",
                "area": "维基教科书食谱",
                "thumb": "",
                "ingredients": parsed["ingredients"],
                "steps": parsed["steps"],
                "source": "wikibooks",
            })
        time.sleep(0.3)
    print(f"[wikibooks] total {len(out)}", flush=True)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--proxy", default="")
    args = ap.parse_args()
    proxy = args.proxy.strip()

    themealdb = build_themealdb(proxy)
    howtocook = build_howtocook(proxy)
    wikibooks = build_wikibooks(proxy)
    payload = {
        "version": 1,
        "built_at": time.strftime("%Y-%m-%d"),
        "themealdb": themealdb,
        "howtocook": howtocook,
        "wikibooks": wikibooks,
    }
    with io.open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))
    size = os.path.getsize(OUT)
    print(f"WROTE {OUT} ({size/1024:.0f} KB) themealdb={len(themealdb)} howtocook={len(howtocook)} wikibooks={len(wikibooks)}", flush=True)


if __name__ == "__main__":
    main()
