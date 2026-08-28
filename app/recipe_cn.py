"""英转中：菜谱术语词典 + MyMemory 免费翻译 + 本地翻译缓存。

策略（设计稿定稿）：
1. 内置「英汉菜谱词典」：食材/单位/烹饪动作 —— 本地直接替换，不花钱、无网络依赖；
2. MyMemory 免费翻译 API（无需 Key）：整句（步骤/未知食材）兜底；
3. 本地缓存：同一段文字只翻译一次。

所有对外函数：
- translate_terms(text)    词典替换（快，准）
- translate_text(text)     词典 + MyMemory + 缓存（尽力而为）
- translate_ingredient(name, amount)  食材行翻译
"""
import hashlib
import json
import re
import sqlite3
import urllib.parse
import urllib.request

from app.database import DATABASE_PATH

# ---------- 内置英汉菜谱词典 ----------

INGREDIENT_ZH = {
    "tomato": "番茄", "tomatoes": "番茄", "egg": "鸡蛋", "eggs": "鸡蛋",
    "pork": "猪肉", "beef": "牛肉", "minced beef": "牛肉末", "chicken": "鸡肉",
    "chicken breast": "鸡胸肉", "chicken thigh": "鸡腿肉", "chicken wings": "鸡翅",
    "chicken wing": "鸡翅", "duck": "鸭肉", "lamb": "羊肉", "fish": "鱼",
    "shrimp": "虾", "prawns": "虾", "rice": "米饭", "noodles": "面条",
    "noodle": "面条", "soy sauce": "生抽", "light soy sauce": "生抽",
    "dark soy sauce": "老抽", "oyster sauce": "蚝油", "sesame oil": "香油",
    "cooking oil": "食用油", "vegetable oil": "植物油", "olive oil": "橄榄油",
    "peanut oil": "花生油", "sunflower oil": "葵花籽油", "butter": "黄油",
    "milk": "牛奶", "garlic": "大蒜", "garlic cloves": "蒜瓣", "ginger": "生姜",
    "scallion": "小葱", "scallions": "小葱", "spring onions": "小葱",
    "spring onion": "小葱", "onion": "洋葱", "red onion": "红洋葱",
    "cabbage": "卷心菜", "bok choy": "小白菜", "napa cabbage": "大白菜",
    "spinach": "菠菜", "carrot": "胡萝卜", "carrots": "胡萝卜",
    "potato": "土豆", "potatoes": "土豆", "mushroom": "蘑菇",
    "mushrooms": "蘑菇", "shiitake": "香菇", "chili": "辣椒", "chilies": "辣椒",
    "chilli": "辣椒", "chili pepper": "辣椒", "green pepper": "青椒",
    "bell pepper": "甜椒", "black pepper": "黑胡椒", "pepper": "胡椒",
    "cucumber": "黄瓜", "eggplant": "茄子", "aubergine": "茄子",
    "broccoli": "西兰花", "cauliflower": "花菜", "celery": "芹菜",
    "corn": "玉米", "tofu": "豆腐", "bean curd": "豆腐", "green beans": "四季豆",
    "peas": "豌豆", "bean sprouts": "豆芽", "bacon": "培根", "sausage": "香肠",
    "ham": "火腿", "steak": "牛排", "pork belly": "五花肉", "pork chops": "猪排",
    "pork chop": "猪排", "salmon": "三文鱼", "cod": "鳕鱼", "tuna": "金枪鱼",
    "bass": "鲈鱼", "crab": "螃蟹", "lobster": "龙虾", "clams": "蛤蜊",
    "mussels": "青口贝", "scallops": "扇贝", "squid": "鱿鱼",
    "cheese": "奶酪", "parmesan": "帕玛森奶酪", "mozzarella": "马苏里拉奶酪",
    "cream": "奶油", "yogurt": "酸奶", "flour": "面粉", "bread flour": "高筋面粉",
    "cornstarch": "玉米淀粉", "corn starch": "玉米淀粉", "starch": "淀粉",
    "sugar": "糖", "brown sugar": "红糖", "powdered sugar": "糖粉",
    "salt": "盐", "sea salt": "海盐", "vinegar": "醋", "rice vinegar": "米醋",
    "balsamic vinegar": "黑醋", "white wine": "白葡萄酒", "red wine": "红葡萄酒",
    "cooking wine": "料酒", "shaoxing wine": "绍兴料酒", "beer": "啤酒",
    "honey": "蜂蜜", "maple syrup": "枫糖浆", "tomato paste": "番茄酱",
    "tomato ketchup": "番茄沙司", "ketchup": "番茄沙司", "mustard": "芥末",
    "mayonnaise": "蛋黄酱", "soy milk": "豆浆", "coconut milk": "椰奶",
    "broth": "高汤", "stock": "高汤", "chicken stock": "鸡汤",
    "beef stock": "牛肉汤", "water": "水", "bread": "面包", "toast": "吐司",
    "pasta": "意大利面", "spaghetti": "意面", "macaroni": "通心粉",
    "lasagne": "千层面", "rice noodles": "米粉", "wonton wrappers": "馄饨皮",
    "dumplings": "饺子", "dumpling": "饺子", "spring rolls": "春卷",
    "cinnamon": "肉桂", "star anise": "八角", "bay leaf": "香叶",
    "bay leaves": "香叶", "cloves": "丁香", "cumin": "孜然", "paprika": "辣椒粉",
    "chili powder": "辣椒粉", "pepper flakes": "辣椒碎", "oregano": "牛至",
    "basil": "罗勒", "thyme": "百里香", "rosemary": "迷迭香", "parsley": "欧芹",
    "cilantro": "香菜", "coriander": "香菜", "mint": "薄荷", "curry": "咖喱",
    "curry powder": "咖喱粉", "turmeric": "姜黄", "sesame seeds": "白芝麻",
    "peanuts": "花生", "cashew": "腰果", "almond": "杏仁", "walnuts": "核桃",
    "walnut": "核桃", "raisins": "葡萄干", "apple": "苹果", "banana": "香蕉",
    "orange": "橙子", "lemon": "柠檬", "lime": "青柠", "strawberry": "草莓",
    "strawberries": "草莓", "blueberry": "蓝莓", "mango": "芒果",
    "pineapple": "菠萝", "peach": "桃子", "pear": "梨", "grape": "葡萄",
    "grapes": "葡萄", "watermelon": "西瓜", "coconut": "椰子",
    "avocado": "牛油果", "kale": "羽衣甘蓝", "zucchini": "西葫芦",
    "pumpkin": "南瓜", "squash": "南瓜", "asparagus": "芦笋", "beets": "甜菜",
    "radish": "萝卜", "daikon": "白萝卜", "chives": "韭菜", "shallot": "红葱头",
    "jasmine rice": "香米", "glutinous rice": "糯米", "hot sauce": "辣酱",
    "mango chutney": "芒果酱", "dijon mustard": "第戎芥末", "anchovy": "鳀鱼",
    "capers": "酸豆", "tomato puree": "番茄泥", "puree": "泥",
}

UNIT_ZH = {
    "tbsp": "汤匙", "tablespoon": "汤匙", "tablespoons": "汤匙", "tbs": "汤匙",
    "tsp": "茶匙", "teaspoon": "茶匙", "teaspoons": "茶匙",
    "cup": "杯", "cups": "杯", "ml": "毫升", "l": "升", "litre": "升",
    "liter": "升", "g": "克", "kg": "千克", "oz": "盎司", "ounce": "盎司",
    "ounces": "盎司", "lb": "磅", "pound": "磅", "pounds": "磅",
    "pinch": "少许", "dash": "少许", "clove": "瓣", "cloves": "瓣",
    "splash": "少许", "handful": "一把", "bunch": "一把", "slice": "片",
    "slices": "片", "piece": "块", "pieces": "块", "head": "颗",
    "medium": "中等大小", "large": "大号", "small": "小号", "can": "罐",
    "package": "包", "pack": "包", "stick": "根", "sprig": "支",
    "drop": "滴", "drops": "滴", "pint": "品脱", "quart": "夸脱",
}

COOK_ZH = {
    "stir-fry": "翻炒", "stir fry": "翻炒", "stir": "翻炒", "fry": "煎炸",
    "pan-fry": "煎", "deep fry": "炸", "simmer": "小火炖", "boil": "煮沸",
    "bake": "烤", "roast": "烤", "grill": "烧烤", "steam": "蒸",
    "braise": "炖煮", "poach": "水煮", "marinate": "腌制", "season": "调味",
    "mix": "混合", "whisk": "搅打", "beat": "搅拌", "knead": "揉面",
    "chop": "切碎", "dice": "切丁", "mince": "剁碎", "slice": "切片",
    "grate": "擦丝", "peel": "去皮", "sear": "煎上色", "reduce": "收汁",
    "drain": "沥干", "rinse": "冲洗", "rest": "静置", "preheat": "预热",
    "heat": "加热", "warm": "温热", "cool": "放凉", "refrigerate": "冷藏",
    "freeze": "冷冻", "thaw": "解冻", "baste": "刷油", "flip": "翻面",
    "toss": "翻拌", "sprinkle": "撒", "garnish": "点缀", "add": "加入",
    "pour": "倒入", "place": "放入", "remove": "取出", "serve": "装盘",
    "cover": "盖上", "uncover": "揭开", "cook": "烹饪", "cooking": "烹饪",
    "prepare": "准备", "sauce": "酱汁", "mixture": "混合物", "bowl": "碗",
    "pot": "锅", "pan": "锅", "skillet": "煎锅", "oven": "烤箱",
    "plate": "盘子", "soup": "汤", "spicy": "辣", "sweet": "甜", "sour": "酸",
    "salty": "咸", "dish": "菜肴", "recipe": "食谱", "ingredients": "食材",
    "ingredient": "食材", "step": "步骤", "steps": "步骤",
    "minute": "分钟", "minutes": "分钟", "until": "直到", "golden": "金黄",
    "tender": "软嫩", "crispy": "酥脆", "evenly": "均匀", "remaining": "剩余",
    "seasoning": "调味", "medium heat": "中火", "high heat": "大火",
    "low heat": "小火", "moderate heat": "中火", "flatbread": "薄饼",
}


def _has_latin(text: str) -> bool:
    return bool(re.search(r"[A-Za-z]", text or ""))


def _build_terms() -> list:
    """字典合并：(word_count, [(pattern, repl)])，多词优先。"""
    merged: dict = {}
    for d in (INGREDIENT_ZH, UNIT_ZH, COOK_ZH):
        for k, v in d.items():
            merged[k.lower()] = v
    groups: dict = {}
    for k, v in merged.items():
        groups.setdefault(len(k.split()), []).append((k, v))
    out = []
    for wc in sorted(groups.keys(), reverse=True):
        out.append((wc, groups[wc]))
    return out


_TERMS = _build_terms()


def translate_terms(text: str) -> str:
    """词典替换。返回替换后的文本；无拉丁字母直接原样返回。"""
    if not text or not _has_latin(text):
        return text or ""
    out = text
    for wc, pairs in _TERMS:
        for k, v in pairs:
            pattern = r"(?<![A-Za-z])" + re.escape(k) + r"(?![A-Za-z])"
            out = re.sub(pattern, v, out, flags=re.IGNORECASE)
    return out


# ---------- MyMemory 免费翻译 ----------

MYMEMORY_URL = "https://api.mymemory.translated.net/get"
_LANGPAIR = "en|zh-CN"


def _mymemory(text: str):
    q = urllib.parse.urlencode({"q": text, "langpair": _LANGPAIR})
    url = f"{MYMEMORY_URL}?{q}"
    req = urllib.request.Request(url, headers={"User-Agent": "what-to-eat-today/1.0"})
    with urllib.request.urlopen(req, timeout=12) as resp:
        data = json.loads(resp.read().decode("utf-8", errors="ignore"))
    td = (data or {}).get("responseData") or {}
    out = td.get("translatedText")
    if out:
        # MyMemory 有时返回 "@@QUALITY@@ 100" 之类的噪音，截断
        if "@@QUALITY@@" in str(out):
            out = str(out).split("@@QUALITY@@")[0].strip()
        return str(out)
    return None


# ---------- 本地缓存 ----------

def _cache_key(text: str) -> str:
    return hashlib.sha1(f"mymemory|{_LANGPAIR}|{text}".encode("utf-8")).hexdigest()


def _get_cache(key: str):
    conn = sqlite3.connect(DATABASE_PATH, check_same_thread=False, isolation_level=None)
    conn.row_factory = sqlite3.Row
    try:
        row = conn.execute("SELECT result FROM translations WHERE key = ?", (key,)).fetchone()
        return row["result"] if row else None
    finally:
        conn.close()


def _put_cache(key: str, source: str, result: str):
    conn = sqlite3.connect(DATABASE_PATH, check_same_thread=False, isolation_level=None)
    try:
        conn.execute(
            "INSERT OR REPLACE INTO translations(key, langpair, source, result) VALUES(?,?,?,?)",
            (key, _LANGPAIR, source, result),
        )
    finally:
        conn.close()


def translate_text(text: str) -> str:
    """整段英转中：缓存 → MyMemory → 词典兜底。已是中文/无字母则原样返回。"""
    text = (text or "").strip()
    if not text:
        return ""
    if not _has_latin(text):
        return text
    key = _cache_key(text)
    cached = _get_cache(key)
    if cached:
        return cached
    try:
        out = _mymemory(text)
        if out:
            _put_cache(key, "mymemory", out)
            return out
    except Exception:
        pass
    out = translate_terms(text)
    _put_cache(key, "dict", out)
    return out


def translate_ingredient(name: str, amount: str = "") -> tuple:
    """翻译食材行：名称走词典/MT，用量只做单位词典替换。返回 (name_zh, amount_zh)。"""
    name_zh = translate_terms(name)
    if name_zh == (name or ""):
        name_zh = translate_text(name)
    amount_zh = translate_terms(amount) or (amount or "")
    return name_zh, amount_zh


def split_amount_unit(amount: str) -> tuple:
    """把用量拆成 (数字, 单位中文)。
    '450g'→('450','克')  '500克'→('500','克')  '1 cup'→('1','杯')
    '2 tbsp'→('2','汤匙')  '1小勺'→('1','小勺')  '适量'→('适量','')
    '1/2 tsp'→('1/2','茶匙')  '1 1/2 cups'→('1 1/2','杯')  '4'→('4','')
    """
    amount = (amount or "").strip()
    if not amount:
        return "", ""
    num = r"(?:\d+\s*\d+/\d+|\d+/\d+|\d+(?:\.\d+)?)"
    m = re.match(r"^(" + num + r")\s*(.*)$", amount)
    if not m:
        return amount, ""
    num_v, unit = m.group(1), m.group(2).strip()
    if not unit:
        return num_v, ""
    unit_zh = translate_terms(unit)
    return num_v, unit_zh