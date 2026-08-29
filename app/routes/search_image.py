"""图片搜索路由 /api/search-image。

多渠道支持（由 system_settings.image_provider 控制，用户可选）：
  1. pixabay        ：默认 Pixabay API（https://pixabay.com/api/docs/）；API Key 从 system_settings.pixabay_api_key 读取
  2. pixabay_zh     ：仍走 Pixabay API，但传给 lang=zh、q 优先使用中文原词，前端跳转到 /zh/ 页面
  3. wikimedia      ：调用 Wikimedia Commons 的 MediaWiki Action API（commons.wikimedia.org/w/api.php），
                      无需 Key；通常国内访问 Wikimedia 较慢或不稳定，所以这里可配合 proxy_url 使用代理。

支持参数：
  - keyword:  查询词（中文 / 英文均可）
  - page:     第几页，从 1 开始，默认 1
  - per_page: 每页几张，范围 [1, 30]，默认 9（用户要"每页 9 张"）
  - provider: 可选覆盖 system_settings.image_provider，便于前端切渠道预览效果

代理：
  - 若 system_settings.proxy_url 非空（形如 http://127.0.0.1:7890），所有对外 HTTP 请求都走该代理
  - 代理通过 urllib.request.ProxyHandler 挂载，支持 http / https / socks5h（需要 PySocks）

重排策略（对 Pixabay）：保留前版的中文拆词、菜名词典、tag 相关性重排 + 噪声黑名单，
对 Wikimedia 返回的结果，把 title / extmetadata.description 转成 tag 字符串后复用同一套打分。
"""
import json
import os
import urllib.parse
import urllib.request
from typing import Dict, List, Optional

from fastapi import APIRouter, Depends, Query
import sqlite3

from app import models
from app.auth import get_current_user
from app.config import get_setting
from app.database import get_db

router = APIRouter(prefix="/api/search-image", tags=["search-image"])

PIXABAY_ENDPOINT = "https://pixabay.com/api/"
WIKIMEDIA_ENDPOINT = "https://commons.wikimedia.org/w/api.php"

# —— 噪声黑名单（非饮料菜名时，命中则扣分）——
NOISE_HINTS = [
    "soda", "soft drink", "beverage", "drink can", "drink cans",
    "can tin", "tin can", "bottle drink", "soda can", "coca cola bottle",
    "coffee cup", "coffee beans", "cup drink", "milk bottle",
    "bread loaf", "ham sandwich", "bacon bread", "sandwich lunch",
    "beautiful wallpaper", "wallpaper background",
]
BEVERAGE_KEYWORDS = [
    "豆浆", "牛奶", "奶茶", "咖啡", "茶", "果汁", "饮品", "可乐", "雪碧", "柠檬水",
    "latte", "coffee", "milk", "juice", "smoothie", "tea", "soda",
]

# —— 中文菜名 -> 英文化查询词（优先级最高，命中率最高）——
DISH_EN: Dict[str, List[str]] = {
    "番茄炒鸡蛋": ["tomato scrambled egg chinese", "tomato egg stir fry", "chinese tomato eggs"],
    "西红柿炒鸡蛋": ["tomato scrambled egg chinese", "tomato egg stir fry"],
    "番茄炒蛋": ["tomato scrambled egg chinese", "tomato egg stir fry"],
    "红烧肉": ["braised pork belly chinese soy sauce", "red cooked pork chinese", "dongpo pork chinese food"],
    "红烧排骨": ["braised pork ribs chinese", "soy sauce pork ribs chinese"],
    "红烧鱼": ["braised fish chinese soy sauce", "whole braised fish chinese"],
    "麻婆豆腐": ["mapo tofu sichuan spicy", "mapo doufu chinese spicy", "spicy tofu sichuan food"],
    "宫保鸡丁": ["kung pao chicken sichuan", "gongbao chicken peanuts spicy chinese"],
    "糖醋里脊": ["sweet and sour pork tenderloin chinese", "tangsu pork chinese"],
    "鱼香肉丝": ["yuxiang shredded pork chinese", "fish fragrant pork chinese"],
    "回锅肉": ["twice cooked pork sichuan", "huiguorou chinese bacon garlic"],
    "水煮肉片": ["sichuan boiled pork spicy", "water cooked pork sichuan chili"],
    "水煮鱼": ["boiled fish fillet sichuan spicy", "sichuan shui zhu yu"],
    "酸菜鱼": ["sour pickled vegetable fish chinese", "suancai yu sichuan fish"],
    "剁椒鱼头": ["chopped chili fish head hunan", "duojiao fish head chinese spicy"],
    "青椒肉丝": ["green pepper shredded pork stir fry", "qingjiao rousi chinese"],
    "土豆丝": ["shredded potato stir fry chinese", "tudou si chinese"],
    "酸辣土豆丝": ["sour spicy shredded potato chinese", "qingjiao tudou si stir fry"],
    "地三鲜": ["dish of three earth potatoes eggplant peppers chinese", "disanxian chinese vegetable stir fry"],
    "干煸四季豆": ["dry fried green beans sichuan", "ganbian sijidou chinese"],
    "白切鸡": ["white cut chicken cantonese", "poached chicken ginger scallion chinese"],
    "可乐鸡翅": ["cola braised chicken wings soy sauce", "coke chicken wings chinese recipe", "braised chicken wings cola sauce"],
    "扬州炒饭": ["yangzhou fried rice chinese", "yeung chow fried rice shrimp chinese"],
    "蛋炒饭": ["chinese egg fried rice", "egg fried rice scallion"],
    "酱油炒饭": ["soy sauce fried rice chinese", "shoyu fried rice"],
    "牛肉炒饭": ["beef fried rice chinese", "beef rice stir fry"],
    "炒饭": ["chinese fried rice", "fried rice with vegetables"],
    "牛肉面": ["chinese beef noodle soup", "lanzhou beef noodles"],
    "红烧牛肉面": ["braised beef noodle soup chinese", "taiwan beef noodle"],
    "番茄鸡蛋面": ["tomato egg noodle soup chinese", "tomato egg noodles"],
    "阳春面": ["plain chinese noodle soup", "soy sauce noodle soup scallion"],
    "担担面": ["dandan noodles sichuan spicy", "chinese sesame paste noodle"],
    "炸酱面": ["zhajiangmian chinese fermented bean paste noodles", "beijing zhajiang noodles"],
    "热干面": ["wuhan hot dry noodles sesame", "regan mian chinese"],
    "兰州拉面": ["lanzhou beef hand pulled noodles", "lanzhou lamian chinese"],
    "饺子": ["chinese dumplings jiaozi pork", "boiled jiaozi chinese"],
    "水饺": ["boiled chinese dumplings jiaozi", "pork cabbage dumplings"],
    "煎饺": ["pan fried dumplings gyoza", "potstickers chinese"],
    "蒸饺": ["steamed chinese dumplings", "steamed jiaozi"],
    "包子": ["steamed pork buns baozi", "chinese baozi bun"],
    "肉包子": ["steamed pork baozi bun chinese", "char siu bao cantonese"],
    "小笼包": ["shanghai xiaolongbao soup dumpling", "xiao long bao steamed"],
    "生煎包": ["shengjian pan fried pork bun", "shanghai pan fried bun"],
    "葱油饼": ["scallion pancake chinese", "cong you bing flaky"],
    "手抓饼": ["taiwan flaky scallion pancake", "shredded hand catch pancake chinese"],
    "馒头": ["steamed bread bun chinese mantou", "plain mantou steamed"],
    "花卷": ["flower roll steamed bread chinese", "huajuan scallion twisted bun"],
    "油条": ["youtiao chinese fried dough stick", "deep fried dough stick breakfast"],
    "豆浆": ["soy milk chinese breakfast", "doujiang soybean milk"],
    "煎饼果子": ["tianjin jianbing chinese crepe", "jianbing guozi pancake egg"],
    "肉夹馍": ["roujiamo chinese hamburger braised pork", "shaanxi meat burger"],
    "皮蛋瘦肉粥": ["century egg lean pork congee", "pork preserved egg rice porridge chinese"],
    "白粥": ["plain chinese congee", "plain rice porridge"],
    "小米粥": ["millet porridge chinese breakfast", "xiaomi congee"],
    "紫菜蛋花汤": ["seaweed egg drop soup chinese", "tomato egg drop soup chinese"],
    "番茄蛋汤": ["tomato egg drop soup chinese", "tomato egg soup bowl"],
    "酸辣汤": ["hot and sour soup chinese", "suanla tang spicy vinegar soup"],
    "清蒸鲈鱼": ["steamed sea bass chinese soy ginger", "cantonese steamed fish"],
    "清蒸鱼": ["steamed whole fish cantonese ginger soy", "qing steamed fish chinese"],
    "红烧带鱼": ["braised hairtail fish chinese soy sauce", "hairtail fish chinese"],
    "烤三文鱼": ["grilled salmon fillet", "seared salmon japanese style"],
    "炸虾": ["fried shrimp tempura", "crispy deep fried prawns"],
    "油焖大虾": ["braised prawns chinese soy sauce", "braised shrimp with soy chinese"],
    "蒜蓉粉丝蒸扇贝": ["garlic glass noodle steamed scallop", "chinese steamed scallop vermicelli"],
    "生蚝": ["oyster raw seafood", "oysters on half shell lemon"],
    "早餐三明治": ["breakfast sandwich egg bacon", "toast breakfast food"],
    "三明治": ["sandwich lunch ham cheese vegetable", "club sandwich toast food"],
    "吐司": ["bread toast butter jam", "toast bread breakfast"],
    "煎饼": ["pancake breakfast maple syrup", "american pancakes stack"],
    "华夫饼": ["waffle breakfast syrup butter", "belgian waffles stack"],
    "贝果": ["bagel cream cheese breakfast", "new york bagel"],
    "可颂": ["croissant french butter pastry breakfast", "croissant bakery"],
    "牛角包": ["croissant french breakfast pastry", "butter croissant"],
    "麦片": ["breakfast cereal bowl milk", "oatmeal porridge breakfast"],
    "牛奶": ["glass of milk breakfast", "milk pour white"],
    "鸡蛋": ["egg breakfast cooked food", "fried egg toast breakfast"],
    "煎蛋": ["fried egg sunny side up breakfast", "pan fried egg toast"],
    "水煮蛋": ["boiled egg breakfast halved", "soft boiled egg"],
    "荷包蛋": ["sunny side up fried egg toast", "fried egg breakfast plate"],
    "茶叶蛋": ["chinese tea egg marbled soy", "taiwan tea egg"],
    "蛋糕": ["cake slice dessert birthday", "chocolate cake dessert plate"],
    "草莓蛋糕": ["strawberry shortcake cream", "strawberry cake dessert"],
    "黑森林蛋糕": ["black forest cake chocolate cherry", "german black forest dessert"],
    "芝士蛋糕": ["cheesecake new york style berry", "cheesecake slice dessert"],
    "提拉米苏": ["tiramisu italian dessert mascarpone coffee", "tiramisu dessert cup"],
    "蛋挞": ["portuguese egg tart custard", "macau egg tart pastry"],
    "曲奇": ["butter cookies chocolate chip", "cookies jar snack"],
    "布丁": ["pudding dessert caramel custard", "creme caramel flan dessert"],
    "冰淇淋": ["ice cream cone scoop chocolate vanilla", "ice cream sundae waffle"],
    "糖葫芦": ["tanghulu candied haws chinese street food", "sugar coated hawthorn stick chinese"],
    "臭豆腐": ["chinese stinky tofu fermented snack", "deep fried fermented tofu snack"],
    "烤冷面": ["korean chinese grilled cold noodle snack", "kao leng mian street food"],
    "关东煮": ["oden japanese hot pot fish cake", "oden egg radish soup japanese"],
    "麻辣烫": ["malatang sichuan hot pot spicy", "chinese spicy skewer hot pot"],
    "火锅": ["chinese hot pot meat vegetable", "sichuan hot pot spicy soup"],
    "海底捞": ["haidilao hot pot chinese", "hot pot shabu shabu meat vegetable"],
    "汉堡": ["burger beef cheese lettuce tomato", "hamburger french fries fast food"],
    "薯条": ["french fries potato ketchup", "crispy golden french fries"],
    "炸鸡": ["fried chicken crispy korean", "kentucky style fried chicken"],
    "披萨": ["pizza italian cheese pepperoni", "pizza margherita basil tomato"],
    "意大利面": ["pasta spaghetti bolognese tomato", "spaghetti carbonara italian"],
    "肉酱意面": ["spaghetti bolognese meat sauce", "pasta spaghetti with meat sauce"],
    "牛排": ["grilled steak ribeye medium rare", "beef steak plate rosemary"],
    "沙拉": ["fresh salad green vegetable bowl", "caesar salad chicken croutons"],
    "寿司": ["sushi japanese rolls salmon", "salmon nigiri sushi japanese"],
    "拉面": ["japanese tonkotsu ramen noodle", "ramen bowl egg chashu pork"],
    "咖喱饭": ["japanese katsu curry rice", "curry rice pork cutlet japanese"],
    "天妇罗": ["tempura japanese shrimp vegetable batter", "shrimp tempura fried japanese"],
    "石锅拌饭": ["korean bibimbap rice vegetable egg", "dolsot bibimbap korean"],
    "部队锅": ["korean army stew budae jjigae", "budae jjigae korean spicy hot pot"],
    "炸鸡排": ["taiwanese fried chicken steak crispy", "fried chicken cutlet snack"],
}

# —— 词级别英译扩充 ——
WORD_EN: Dict[str, str] = {
    "鸡蛋": "egg", "蛋": "egg",
    "番茄": "tomato", "西红柿": "tomato",
    "土豆": "potato", "马铃薯": "potato",
    "青椒": "green pepper", "辣椒": "chili pepper",
    "葱": "scallion green onion",
    "姜": "ginger", "蒜": "garlic", "洋葱": "onion",
    "胡萝卜": "carrot", "白菜": "napa cabbage chinese",
    "菠菜": "spinach", "茄子": "eggplant", "黄瓜": "cucumber",
    "玉米": "corn maize", "蘑菇": "mushroom", "豆腐": "tofu",
    "米饭": "rice", "饭": "rice", "面": "noodles", "面条": "noodles", "粉": "noodles vermicelli",
    "馒头": "bread", "粥": "congee porridge", "汤": "soup",
    "猪肉": "pork", "排骨": "pork ribs", "五花肉": "pork belly",
    "牛肉": "beef", "牛排": "beef steak",
    "鸡肉": "chicken", "鸡翅": "chicken wing", "鸡腿": "chicken leg",
    "羊肉": "lamb",
    "鱼": "fish", "虾": "shrimp prawn", "蟹": "crab",
    "扇贝": "scallop", "生蚝": "oyster",
    "三文鱼": "salmon", "鲈鱼": "sea bass", "带子": "scallop",
    "炒": "stir fry", "煎": "pan fry", "炸": "deep fry",
    "烤": "grill roast bbq", "蒸": "steam", "炖": "stew braise", "煮": "boil cook",
    "拌": "toss salad", "红烧": "braise soy sauce",
    "糖醋": "sweet sour", "酸辣": "hot sour spicy", "麻辣": "sichuan numbing spicy chili",
    "蒜蓉": "garlic", "八宝": "eight treasure", "五香": "five spice",
    "黑椒": "black pepper", "蜜汁": "honey glazed", "铁板": "teppanyaki iron plate",
    "早餐": "breakfast", "午餐": "lunch", "晚餐": "dinner",
    "甜品": "dessert", "小吃": "snack street food",
    "中国": "chinese food", "中式": "chinese style",
    "四川": "sichuan spicy", "川菜": "sichuan chinese food",
    "粤菜": "cantonese chinese food", "湘菜": "hunan spicy chinese",
    "上海": "shanghai style", "广东": "cantonese", "台湾": "taiwanese", "香港": "hong kong",
    "日本": "japanese", "日料": "japanese cuisine",
    "韩国": "korean", "韩式": "korean style",
    "西餐": "western food", "意式": "italian", "法式": "french", "美式": "american",
}

GENERAL_HINTS = {"chinese", "asian", "cuisine", "cooking", "restaurant", "gourmet",
                 "sichuan", "cantonese", "hunan", "shanghai", "taiwanese",
                 "korean", "japanese", "hongkong", "american",
                 "western", "italian", "french", "breakfast", "lunch", "dinner",
                 "dessert", "snack", "coffee", "tea"}
SPECIFIC_HINTS = {"stir", "fry", "braise", "wok", "steam", "boil", "grill",
                  "spicy", "roasted", "soup", "sauce", "soy", "roast", "noodle",
                  "porridge", "congee", "dumpling", "baozi", "fried_rice", "rice"}

# —— 代理：如果 proxy_url 非空，构造带 ProxyHandler 的 opener ——
def _proxy_userinfo(parsed) -> str:
    """把 urlparse 里的 username/password 还原成 'user:pass@'（为空则返回 ''）。"""
    if not parsed.username:
        return ""
    ui = parsed.username
    if parsed.password:
        ui += ":" + parsed.password
    return ui + "@"


def _make_http_opener(proxy_url: str):
    proxy_url = (proxy_url or "").strip()
    if not proxy_url:
        return None
    from urllib.parse import urlparse
    parsed = urlparse(proxy_url)
    scheme = parsed.scheme or "http"
    host = parsed.hostname
    if not host:
        return None
    # 容器内 127.0.0.1/localhost 指向容器自身，宿主机代理需改用 host.docker.internal
    if host in ("127.0.0.1", "localhost") and os.path.exists("/.dockerenv"):
        host = "host.docker.internal"
    proxy_host = host + (f":{parsed.port}" if parsed.port else "")
    userinfo = _proxy_userinfo(parsed)
    full = f"{scheme}://{userinfo}{proxy_host}"
    # socks5h 让 DNS 解析走代理（适合国内翻墙访问 Wikimedia），urllib 默认不支持 socks5，
    # 如果本机装了 PySocks / socks 模块，则使用；否则退回 http/https ProxyHandler
    if scheme.startswith("socks"):
        try:
            import socks  # type: ignore
            from sockshandler import SocksiPyHandler  # type: ignore
            socks_type = socks.SOCKS5 if scheme in ("socks5", "socks5h") else socks.SOCKS4
            rdns = (scheme == "socks5h")
            port = parsed.port or (1080 if scheme in ("socks5", "socks5h") else 1080)
            return urllib.request.build_opener(SocksiPyHandler(
                socks_type, host, port, rdns=rdns,
                username=parsed.username or None, password=parsed.password or None))
        except Exception:
            # 没装 PySocks：退化为 http 代理（多数国内翻墙客户端同时提供 http 代理端口）
            return urllib.request.build_opener(urllib.request.ProxyHandler({
                "http": full,
                "https": full,
            }))
    return urllib.request.build_opener(urllib.request.ProxyHandler({
        "http": full,
        "https": full,
    }))


def _urlopen(url: str, headers: Dict[str, str], timeout: int = 12, proxy_url: str = ""):
    req = urllib.request.Request(url, headers=dict(headers or {}, **{"User-Agent": "what-to-eat-today/1.0"}))
    opener = _make_http_opener(proxy_url)
    if opener is None:
        return urllib.request.urlopen(req, timeout=timeout)
    return opener.open(req, timeout=timeout)


def _is_chinese(s: str) -> bool:
    return any("\u4e00" <= ch <= "\u9fff" for ch in s)


def build_query_candidates(zh_kw: str) -> List[str]:
    k = zh_kw.strip()
    if not k:
        return []
    candidates: List[str] = []
    seen = set()

    def add(q: str) -> None:
        q = " ".join(q.split())
        if not q or q in seen:
            return
        seen.add(q)
        candidates.append(q)

    for dish_name in sorted(DISH_EN.keys(), key=len, reverse=True):
        if dish_name in k:
            for en in DISH_EN[dish_name]:
                add(en)
    suffixes: List[str] = []
    tail_kw = k
    if tail_kw.endswith("饭"): suffixes += ["chinese fried rice", "rice dish chinese"]
    elif tail_kw.endswith("面"): suffixes += ["chinese noodles", "noodle soup chinese"]
    elif tail_kw.endswith("粥"): suffixes += ["chinese congee", "rice porridge asian"]
    elif tail_kw.endswith("汤"): suffixes += ["soup bowl chinese", "asian hot soup"]
    elif tail_kw.endswith("饺") or tail_kw.endswith("饺子"): suffixes += ["jiaozi dumplings chinese", "dumplings pork chinese"]
    elif tail_kw.endswith("包") or tail_kw.endswith("包子"): suffixes += ["steamed bun baozi chinese", "baozi asian bread"]
    elif tail_kw.endswith("糕") or tail_kw.endswith("蛋糕"): suffixes += ["dessert cake slice", "cake pastry food"]
    elif tail_kw.endswith("饼"): suffixes += ["pancake chinese", "flatbread pastry"]
    elif tail_kw.endswith("鱼"): suffixes += ["fish dish chinese cooking", "seafood fish plate"]
    elif tail_kw.endswith("肉"): suffixes += ["meat dish braised chinese", "pork beef plate cooking"]
    elif tail_kw.endswith("鸡"): suffixes += ["chinese chinese dish", "asian chicken cooking"]
    elif tail_kw.endswith("豆腐") or tail_kw.endswith("腐"): suffixes += ["tofu dish chinese", "asian soy bean curd"]
    elif tail_kw.endswith("排") or tail_kw.endswith("排骨"): suffixes += ["pork ribs chinese", "ribs braised soy"]
    for sfx in suffixes:
        add(k + " " + sfx)
    replaced = k
    for zh, en in sorted(WORD_EN.items(), key=lambda kv: len(kv[0]), reverse=True):
        if zh in replaced:
            replaced = replaced.replace(zh, " " + en + " ")
    if replaced != k and _is_chinese(replaced):
        cleaned = " ".join(w for w in replaced.split() if not _is_chinese(w))
        if cleaned.strip():
            add(cleaned.strip() + " chinese food")
    elif replaced != k:
        add(replaced + " chinese dish")
    for tail in [
        "chinese food dish recipe", "chinese cooking asian food",
        "asian stir fry plate meal", "cuisine cooking kitchen plate",
    ]:
        add(k + " " + tail)
    add(k)
    return candidates


def _fetch_pixabay(api_key: str, q: str, per_page: int, page: int, lang: str, proxy_url: str) -> List[dict]:
    params = urllib.parse.urlencode({
        "key": api_key,
        "q": q,
        "per_page": per_page,
        "page": max(1, int(page)),
        "image_type": "photo",
        "safesearch": "true",
        "category": "food",
        "lang": lang,  # zh/en/ja 等，默认 en
    })
    url = f"{PIXABAY_ENDPOINT}?{params}"
    with _urlopen(url, {}, timeout=15, proxy_url=proxy_url) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    return data.get("hits") or []


def _fetch_wikimedia_once(gsrsearch: str, per_page: int, page: int, proxy_url: str) -> List[dict]:
    """用给定 gsrsearch 拉一次 Wikimedia Commons 搜索结果（不重排，保留官方相关度顺序）。"""
    params = urllib.parse.urlencode({
        "action": "query",
        "format": "json",
        "generator": "search",
        "gsrsearch": gsrsearch,
        "gsrnamespace": 6,  # 6=文件
        "gsrlimit": per_page,
        "gsroffset": max(0, (max(1, int(page)) - 1) * per_page),
        "prop": "imageinfo",
        "iiprop": "url|size|mime|extmetadata",
        "iiurlwidth": 640,
        "iiurlheight": 640,
    })
    url = f"{WIKIMEDIA_ENDPOINT}?{params}"
    with _urlopen(url, {"Accept": "application/json"}, timeout=20, proxy_url=proxy_url) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    pages = (data.get("query") or {}).get("pages") or {}
    hits: List[dict] = []
    for pid, p in pages.items():
        infos = p.get("imageinfo") or []
        if not infos:
            continue
        info = infos[0]
        thumb = info.get("thumburl") or info.get("url") or ""
        full = info.get("url") or thumb
        meta = info.get("extmetadata") or {}
        # 从 extmetadata / title 里拼一个类似 Pixabay tags 的字段（便于展示/调试）
        title_tokens = (p.get("title") or "").replace("File:", " ").replace("_", " ").replace(".", " ")
        desc_obj = meta.get("ImageDescription") or {}
        desc = desc_obj.get("value") if isinstance(desc_obj, dict) else str(desc_obj or "")
        obj_date = (meta.get("DateTimeOriginal") or {}).get("value", "") if isinstance(meta.get("DateTimeOriginal"), dict) else ""
        pseudo_tags = f"{title_tokens} {desc} {obj_date}".lower()
        # 过滤 svg/非位图
        mime = info.get("mime") or ""
        if mime and not mime.startswith("image/"):
            continue
        width = info.get("width") or 0
        height = info.get("height") or 0
        hits.append({
            "id": pid,
            "tags": pseudo_tags,
            "pageURL": info.get("descriptionshorturl") or "",
            "webformatURL": full,
            "previewURL": thumb,
            "imageWidth": width,
            "imageHeight": height,
            "type": mime.replace("image/", ""),
            "previewWidth": 640,
            "previewHeight": 640,
        })
    return hits


def _fetch_wikimedia(keyword: str, per_page: int, page: int, lang: str, proxy_url: str) -> List[dict]:
    """调用 https://commons.wikimedia.org/w/api.php

    尽量贴近 Wikimedia 官网的搜索行为：先用原词搜（中文就原中文词），
    若无结果再退回"原词+食物"、再退回中→英翻译词。命中即返回，不在此重排。
    """
    candidates: List[str] = []
    seen = set()

    def add(q: str):
        q = " ".join(q.split())
        if q and q not in seen:
            seen.add(q)
            candidates.append(q)

    raw = (keyword or "").strip()
    if not raw:
        raw = "food"
    add(raw)
    if _is_chinese(raw):
        add(raw + " 食物")
        for en in build_query_candidates(raw)[:3]:
            add(en)
    add("food")

    last_err = None
    for c in candidates:
        try:
            hits = _fetch_wikimedia_once(c, per_page, page, proxy_url)
            if hits:
                print(f"[img-search:wikimedia] kw={keyword!r} gsrsearch={c!r} raw={len(hits)}", flush=True)
                return hits
        except Exception as e:
            last_err = f"{type(e).__name__}: {e}"
            print(f"[img-search:wikimedia] kw={keyword!r} gsrsearch={c!r} FAIL {last_err}", flush=True)
            continue
    if last_err and not proxy_url:
        print("[img-search:wikimedia] 未配置代理，Wikimedia 失败可能源于网络连通，可在管理中心→系统设置填入代理后重试", flush=True)
    return []


def _score_and_rerank(hits: List[dict], zh_kw: str, en_queries: List[str]) -> List[dict]:
    if not hits:
        return hits

    raw_tokens: List[str] = []
    for q in en_queries:
        for token in q.lower().split():
            if len(token) > 2:
                raw_tokens.append(token)
    for zh, en in WORD_EN.items():
        if zh in zh_kw:
            for token in en.lower().split():
                if len(token) > 2:
                    raw_tokens.append(token)
    raw_tokens = [t for t in raw_tokens if t not in {
        "the", "and", "with", "from", "into", "dish", "food", "cuisine",
        "recipe", "plate", "meal", "style",
    }]

    specific_tokens: List[str] = []
    general_tokens: List[str] = []
    for t in raw_tokens:
        if t in GENERAL_HINTS:
            general_tokens.append(t)
        else:
            specific_tokens.append(t)

    is_beverage = any(b in zh_kw.lower() for b in [w.lower() for w in BEVERAGE_KEYWORDS])

    weighted: List[tuple[int, int, dict]] = []
    for idx, h in enumerate(hits):
        tag_str = ((h.get("tags") or "") + " " + (h.get("type") or "") + " " + (h.get("pageURL") or "")).lower()
        score = 0

        spec_seen: set = set()
        for tok in specific_tokens:
            if tok in tag_str and tok not in spec_seen:
                score += 5
                spec_seen.add(tok)
        gen_seen: set = set()
        for tok in general_tokens:
            if tok in tag_str and tok not in gen_seen:
                score += 1
                gen_seen.add(tok)

        hint_hits = 0
        for hint in SPECIFIC_HINTS:
            if hint in tag_str:
                score += 1
                hint_hits += 1

        hits_specific = len(spec_seen) + hint_hits
        hits_general_only = len(gen_seen)
        if hits_specific == 0 and hits_general_only <= 2:
            score -= 8
        if hits_specific >= 2:
            score += 3
        if hits_specific >= 4:
            score += 2

        # 长宽比惩罚：极度竖版/极度横版的美食封面（> 3:1 或 < 1:3）不优先
        w = int(h.get("imageWidth") or 0)
        hi = int(h.get("imageHeight") or 0)
        if w and hi:
            ratio = w / hi
            if ratio > 3 or ratio < 1 / 3:
                score -= 2

        if not is_beverage:
            for noise in NOISE_HINTS:
                if noise in tag_str:
                    score -= 4

        order_bonus = max(0, 10 - idx // 3)
        score += order_bonus
        weighted.append((-score, idx, h))

    weighted.sort(key=lambda t: (t[0], t[1]))
    return [h for _, _, h in weighted]


@router.get("", response_model=List[models.SearchImageItem])
def search_image(
    keyword: str = Query(..., min_length=1, max_length=120),
    page: int = Query(1, ge=1, le=20),
    per_page: int = Query(9, ge=1, le=30),
    provider: Optional[str] = Query(None, pattern="^(pixabay|pixabay_zh|wikimedia)$"),
    user=Depends(get_current_user),
    conn: sqlite3.Connection = Depends(get_db),
):
    """多渠道图片搜索。"""
    # 1. 读系统设置
    prov = ((provider or get_setting("image_provider", "pixabay", conn=conn) or "pixabay").strip().lower()
            or "pixabay")
    api_key = (get_setting("pixabay_api_key", "", conn=conn) or "").strip()
    proxy_url = (get_setting("proxy_url", "", conn=conn) or "").strip()

    # 2. 根据渠道取原始 hits（单请求，不再多 query 合并——避免翻页跨页重复/跳号）
    hits: List[dict] = []
    queries = build_query_candidates(keyword)

    if prov in ("pixabay", "pixabay_zh"):
        if not api_key:
            return []  # 无 Key → 返回空，前端降级到手动输入
        lang = "zh" if prov == "pixabay_zh" else "en"
        # pixabay_zh 优先用中文原词（第一个 query 强制放 keyword）
        if prov == "pixabay_zh":
            q_list = [keyword.strip()] + [q for q in queries if q != keyword.strip()]
        else:
            q_list = queries or [keyword.strip()]
        last_err = None
        for q in q_list[:5]:
            try:
                hits = _fetch_pixabay(api_key, q, per_page, page, lang, proxy_url)
                if hits:
                    break
            except Exception as e:
                last_err = f"{type(e).__name__}: {e}"
                print(f"[img-search:{prov}] kw={keyword!r} q={q!r} FAIL {last_err}", flush=True)
                continue
        if not hits and last_err:
            print(f"[img-search:{prov}] kw={keyword!r} all_queries_failed last_err={last_err}", flush=True)
    elif prov == "wikimedia":
        try:
            # Wikimedia 直接用中文/英文原词
            hits = _fetch_wikimedia(keyword, per_page, page, "zh" if _is_chinese(keyword) else "en", proxy_url)
        except Exception as e:
            print(f"[img-search:wikimedia] kw={keyword!r} FAIL {type(e).__name__}: {e}", flush=True)
            # Wikimedia 在国内经常超时，失败时如果有 proxy_url 为空，打印一下额外提示
            if not proxy_url:
                print("[img-search:wikimedia] 未配置代理，Wikimedia 失败可能源于网络连通，可在管理中心→系统设置填入代理后重试", flush=True)
            hits = []
    else:
        return []

    # 3. 重排：Wikimedia 用官方返回顺序（原生搜索已够相关，且其搜索按中文词工作），
    #    只有 Pixabay 才做中文→英文关键词的重排
    if prov == "wikimedia":
        ranked = hits
    else:
        ranked = _score_and_rerank(hits, zh_kw=keyword, en_queries=queries[:3] or [keyword])

    # 4. 规范化输出
    out: List[dict] = []
    for item in ranked:
        full = item.get("webformatURL") or item.get("largeImageURL") or item.get("url") or ""
        thumb = item.get("previewURL") or item.get("thumburl") or full
        if not full:
            continue
        out.append({"url": full, "thumb": thumb})

    print(f"[img-search:{prov}] kw={keyword!r} page={page} per_page={per_page} raw={len(hits)} out={len(out)}", flush=True)
    return out
