"""食谱 API 路由 /api/recipe-api/*。

无 Key 方案（设计稿定稿）：
1. /search      —— TheMealDB 搜索（中文关键词先用现有词典转英文召回）
2. /prepare     —— 把选中菜谱做「英转中」处理，返回可直接填充表单的结构
3. /parse-paste —— 粘贴文本解析（标题/食材/步骤），支持中文笔记（如小红书）
"""
import concurrent.futures as cf
import hashlib
import json
import re
import sqlite3
import urllib.parse
import urllib.request
from typing import List, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.auth import get_current_user
from app.config import get_setting
from app.database import DATABASE_PATH, get_db
from app.recipe_cn import (
    split_amount_unit, translate_ingredient, translate_text, _has_latin,
)
from app.routes.search_image import _is_chinese, _make_http_opener, DISH_EN, WORD_EN

router = APIRouter(prefix="/api/recipe-api", tags=["recipe-api"])

THEMEALDB_ENDPOINT = "https://www.themealdb.com/api/json/v1/1"
MYMEMORY_URL = "https://api.mymemory.translated.net/get"
_LANGPAIR = "en|zh-CN"

# 搜索词翻译专用补充（面向 TheMealDB 召回，不在图片搜索词典里的）
_DISH_EN_ADDON = {
    "红烧排骨": ["braised pork ribs chinese", "soy sauce pork ribs chinese"],
    "糖醋排骨": ["sweet and sour pork ribs chinese", "tangcu spare ribs"],
    "糖醋里脊": ["sweet and sour pork tenderloin chinese", "tangsu pork chinese"],
    "鱼香肉丝": ["yuxiang shredded pork chinese", "fish fragrant pork chinese"],
    "回锅肉": ["twice cooked pork sichuan", "huiguorou chinese"],
    "水煮肉片": ["sichuan boiled pork spicy", "water cooked pork sichuan"],
    "水煮鱼": ["boiled fish fillet sichuan spicy", "sichuan shui zhu yu"],
    "酸菜鱼": ["sour pickled vegetable fish chinese", "suancai yu sichuan"],
    "剁椒鱼头": ["chopped chili fish head hunan", "duojiao fish head chinese spicy"],
    "青椒肉丝": ["green pepper shredded pork stir fry", "qingjiao rousi chinese"],
    "土豆丝": ["shredded potato stir fry chinese", "tudou si chinese"],
    "酸辣土豆丝": ["sour spicy shredded potato chinese"],
    "地三鲜": ["dish of three earth potatoes eggplant peppers chinese"],
    "干煸四季豆": ["dry fried green beans sichuan"],
    "白切鸡": ["white cut chicken cantonese", "poached chicken ginger scallion chinese"],
    "可乐鸡翅": ["cola braised chicken wings soy sauce", "braised chicken wings cola sauce"],
    "红烧鱼": ["braised fish chinese soy sauce", "whole braised fish chinese"],
    "清蒸鲈鱼": ["steamed sea bass chinese soy ginger", "cantonese steamed fish"],
    "清蒸鱼": ["steamed whole fish cantonese ginger soy"],
    "红烧带鱼": ["braised hairtail fish chinese soy sauce"],
    "油焖大虾": ["braised prawns chinese soy sauce"],
    "蒜蓉粉丝蒸扇贝": ["garlic glass noodle steamed scallop"],
    "红烧茄子": ["braised eggplant chinese", "stewed eggplant chinese"],
    "干煸豆角": ["dry fried green beans sichuan"],
    "肉末茄子": ["minced meat eggplant chinese", "shredded pork eggplant"],
    "麻婆豆腐": ["mapo tofu sichuan spicy", "mapo doufu chinese spicy"],
    "宫保鸡丁": ["kung pao chicken sichuan", "gongbao chicken peanuts spicy chinese"],
    "红烧肉": ["braised pork belly chinese soy sauce", "red cooked pork chinese"],
    "梅菜扣肉": ["braised pork with preserved vegetable", "meicai kourou chinese"],
    "啤酒鸭": ["beer duck chinese", "braised duck with beer chinese"],
    "咖喱鸡": ["curry chicken asian", "chinese curry chicken"],
    "咖喱牛肉": ["curry beef asian", "chinese curry beef"],
    "咖喱土豆": ["curry potato asian", "chinese curry potato"],
    "土豆炖牛肉": ["braised beef potato chinese", "beef stew potato chinese"],
    "番茄牛腩": ["tomato beef brisket chinese", "tomato beef stew chinese"],
    "洋葱炒牛肉": ["onion beef stir fry chinese"],
    "木耳炒肉": ["wood ear mushroom pork stir fry chinese"],
    "木须肉": ["mu shu pork chinese egg", "mushroom pork egg stir fry"],
    "咕咾肉": ["sweet and sour pork chinese", "gu lau rou sweet and sour pork"],
    "糖醋里脊": ["sweet and sour pork tenderloin chinese"],
    "蒜蓉西兰花": ["garlic broccoli chinese stir fry"],
    "蚝油生菜": ["oyster sauce lettuce chinese", "stir fry lettuce chinese"],
    "白灼菜心": ["blanched chinese broccoli cantonese"],
    "蒜蓉粉丝": ["garlic glass noodle vermicelli chinese"],
    "蛋饺": ["egg dumpling chinese", "stuffed egg wrap chinese"],
    "腐竹烧肉": ["dried bean curd with pork chinese"],
    "粉蒸肉": ["steamed pork with rice flour chinese", "fenzheng rou chinese"],
    "粉蒸排骨": ["steamed pork ribs with rice flour chinese"],
    "蒸蛋": ["steamed egg custard chinese"],
    "西红柿鸡蛋": ["tomato scrambled egg chinese", "tomato egg stir fry"],
    "西红柿鸡蛋汤": ["tomato egg soup chinese"],
    "西红柿鸡蛋面": ["tomato egg noodle soup chinese"],
    "蛋花汤": ["egg drop soup chinese"],
    "紫菜蛋花汤": ["seaweed egg drop soup chinese"],
    "豆腐汤": ["tofu soup chinese"],
    "番茄豆腐": ["tomato tofu chinese"],
    "麻婆豆腐": ["mapo tofu sichuan spicy", "mapo doufu chinese"],
    "家常豆腐": ["home style tofu chinese", "braised tofu chinese"],
    "千叶豆腐": ["braised sheet tofu chinese"],
    "红烧豆腐": ["braised tofu chinese soy sauce"],
    "干锅花菜": ["dry pot cauliflower chinese"],
    "干锅花菜": ["dry pot cauliflower chinese"],
    "鱼香茄子": ["yuxiang eggplant chinese"],
    "地三鲜": ["dish of three earth potatoes eggplant peppers chinese"],
    "红烧鸡块": ["braised chicken chunks chinese"],
    "可乐鸡翅": ["cola braised chicken wings chinese"],
    "盐焗鸡": ["salt baked chicken chinese", "salted chicken chinese"],
    "葱油鸡": ["scallion oil chicken chinese", "soy dipping chicken chinese"],
    "三杯鸡": ["three cup chicken taiwanese", "san bei ji chinese"],
    "黄焖鸡": ["braised chicken chinese", "huang men ji chinese"],
    "小鸡炖蘑菇": ["chicken mushroom stew chinese", "dinner chicken mushroom chinese"],
    "小鸡炖蘑菇": ["chicken mushroom stew chinese"],
    "香菇滑鸡": ["shiitake chicken chinese", "mushroom chicken chinese"],
    "盐焗鸡翅": ["salt baked chicken wings chinese"],
    "蜜汁叉烧": ["sweet braised pork chinese bbq", "char siu bbq pork chinese"],
    "叉烧肉": ["sweet braised pork bbq chinese", "char siu chinese"],
    "蒜香排骨": ["garlic pork ribs chinese baked"],
    "糖醋里脊": ["sweet and sour pork tenderloin chinese"],
    "椒盐排骨": ["salt and pepper pork ribs chinese fried"],
    "可乐鸡腿": ["cola braised chicken leg chinese"],
    "啤酒鸭": ["beer duck chinese braised"],
    "咖喱土豆": ["curry potato asian", "chinese curry potato"],
    "土豆丝饼": ["shredded potato pancake chinese", "potato pancake chinese"],
    "西红柿鸡蛋": ["tomato scrambled egg chinese", "tomato egg stir fry"],
    "西红柿鸡蛋面": ["tomato egg noodle soup chinese"],
    "西红柿鸡蛋汤": ["tomato egg soup chinese"],
    "紫菜蛋花汤": ["seaweed egg drop soup chinese"],
    "蛋花汤": ["egg drop soup chinese"],
    "番茄蛋汤": ["tomato egg drop soup chinese"],
    "豆腐汤": ["tofu soup chinese"],
    "白菜豆腐汤": ["napa cabbage tofu soup chinese"],
    "酸辣汤": ["hot and sour soup chinese", "suanla tang spicy vinegar soup"],
    "西红柿排骨汤": ["tomato pork ribs soup chinese"],
    "排骨玉米汤": ["pork ribs corn soup chinese"],
    "萝卜排骨汤": ["radish pork ribs soup chinese"],
    "海带排骨汤": ["kelp pork ribs soup chinese"],
    "冬瓜排骨汤": ["winter melon pork ribs soup chinese"],
    "莲藕排骨汤": ["lotus root pork ribs soup chinese"],
    "玉米排骨汤": ["corn pork ribs soup chinese"],
    "山药排骨汤": ["chinese yam pork ribs soup"],
    "萝卜炖牛腩": ["radish beef brisket stew chinese"],
    "白萝卜炖牛肉": ["daikon beef brisket stew chinese"],
    "牛腩煲": ["beef brisket hotpot chinese"],
    "番茄牛腩": ["tomato beef brisket chinese"],
    "土豆炖牛肉": ["braised beef potato chinese"],
    "土豆牛肉": ["potato beef chinese"],
    "洋葱炒牛肉": ["onion beef stir fry chinese"],
    "黑椒牛柳": ["black pepper beef strips chinese"],
    "蒜苗炒肉": ["garlic scallion pork stir fry chinese"],
    "韭黄炒蛋": ["chive egg stir fry chinese"],
    "韭菜鸡蛋": ["chive egg stir fry chinese"],
    "韭黄炒肉": ["chive pork stir fry chinese"],
    "韭菜盒子": ["chive pocket chinese pan cake", "leek pancake chinese"],
    "韭菜盒子": ["chive pocket chinese pan cake"],
    "韭菜炒蛋": ["chive egg stir fry chinese"],
    "青椒炒蛋": ["green pepper egg stir fry chinese"],
    "苦瓜炒蛋": ["bitter gourd egg stir fry chinese"],
    "丝瓜炒蛋": ["loofah egg stir fry chinese"],
    "西葫芦炒蛋": ["zucchini egg stir fry chinese"],
    "黄瓜炒蛋": ["cucumber egg stir fry chinese"],
    "番茄炒蛋": ["tomato scrambled egg chinese", "tomato egg stir fry", "chinese tomato eggs"],
    "西红柿炒蛋": ["tomato scrambled egg chinese", "tomato egg stir fry"],
    "蒜苔炒肉": ["garlic scapes pork stir fry chinese"],
    "蒜苔炒鸡蛋": ["garlic scapes egg stir fry chinese"],
    "豆角炒肉": ["green beans pork stir fry chinese"],
    "扁豆炒肉": ["flat beans pork stir fry chinese"],
    "豆角烧茄子": ["green bean eggplant chinese"],
    "红烧肉": ["braised pork belly chinese soy sauce"],
    "东坡肉": ["dongpo pork chinese", "braised pork belly soy sauce chinese"],
    "梅菜扣肉": ["braised pork with preserved vegetable chinese"],
    "红烧肉炖土豆": ["braised pork potato chinese"],
    "红烧猪肉": ["braised pork chinese soy sauce"],
    "梅菜扣肉": ["braised pork with preserved vegetable chinese"],
    "回锅肉": ["twice cooked pork sichuan"],
    "蒜苔炒肉丝": ["garlic scapes shredded pork chinese"],
    "芹菜炒肉": ["celery pork stir fry chinese"],
    "芹菜牛肉": ["celery beef stir fry chinese"],
    "土豆丝炒肉": ["shredded potato pork stir fry chinese"],
    "洋葱炒肉": ["onion pork stir fry chinese"],
    "洋葱炒蛋": ["onion egg stir fry chinese"],
    "洋葱牛肉": ["onion beef stir fry chinese"],
    "杏鲍菇炒肉": ["king oyster mushroom pork stir fry chinese"],
    "香菇炒肉": ["shiitake mushroom pork chinese"],
    "金针菇炒肉": ["enoki mushroom pork stir fry chinese"],
    "平菇炒肉": ["oyster mushroom pork chinese"],
    "蘑菇炒蛋": ["mushroom egg stir fry chinese"],
    "木耳炒鸡蛋": ["wood ear mushroom egg chinese"],
    "木耳肉丝": ["wood ear shredded pork chinese"],
    "醋溜白菜": ["napa cabbage chinese stir fry vinegar", "vinegar cabbage chinese"],
    "醋溜白菜": ["napa cabbage chinese stir fry vinegar"],
    "手撕包菜": ["hand torn cabbage chinese", "stir fry cabbage chinese"],
    "蒜蓉西兰花": ["garlic broccoli chinese stir fry"],
    "蚝油生菜": ["oyster sauce lettuce chinese"],
    "白灼菜心": ["blanched chinese broccoli cantonese"],
    "炒空心菜": ["water spinach chinese stir fry", "kong xin cai chinese"],
    "蒜蓉空心菜": ["garlic water spinach chinese"],
    "蒜蓉茼蒿": ["garlic crown daisy chinese"],
    "清炒时蔬": ["stir fried seasonal vegetables chinese"],
    "蚝油生菜": ["oyster sauce lettuce chinese"],
    "红烧鲫鱼": ["braised crucian fish chinese soy"],
    "清蒸鲈鱼": ["steamed sea bass chinese soy ginger"],
    "干烧鱼": ["dry braised fish chinese"],
    "糖醋鲤鱼": ["sweet and sour carp chinese"],
    "红烧带鱼": ["braised hairtail fish chinese soy sauce"],
    "红烧鳕鱼": ["braised cod fish chinese"],
    "可乐鸡翅": ["cola braised chicken wings chinese"],
    "奥尔良鸡翅": ["orleans chicken wings chinese"],
    "蜜汁叉烧": ["sweet braised pork chinese bbq"],
    "炸酱面": ["zhajiangmian chinese fermented bean paste noodles"],
    "热干面": ["wuhan hot dry noodles sesame"],
    "担担面": ["dandan noodles sichuan spicy"],
    "凉面": ["cold noodles chinese sesame"],
    "鸡丝凉面": ["shredded chicken cold noodles chinese"],
    "葱油拌面": ["scallion oil noodles chinese"],
    "阳春面": ["plain chinese noodle soup"],
    "牛肉面": ["chinese beef noodle soup"],
    "兰州拉面": ["lanzhou beef hand pulled noodles"],
    "鸡蛋面": ["egg noodle soup chinese"],
    "面条": ["chinese noodle soup", "hand made noodles chinese"],
    "刀削面": ["knife cut noodles chinese"],
    "烩面": ["stewed wide noodles chinese"],
    "饸饹面": ["heluo noodles chinese"],
    "炸酱面": ["zhajiangmian chinese"],
    "打卤面": ["dalu noodle chinese"],
    "拌面": ["mixed noodles chinese"],
    "阳春面": ["plain chinese noodle soup"],
    "鸡蛋面": ["egg noodle soup chinese"],
    "西红柿鸡蛋面": ["tomato egg noodle soup chinese"],
    "鸡蛋饼": ["egg pancake chinese", "scallion pancake chinese"],
    "鸡蛋灌饼": ["egg stuffed pancake chinese"],
    "葱花饼": ["scallion pancake chinese"],
    "手抓饼": ["taiwan flaky scallion pancake"],
    "葱油饼": ["scallion pancake chinese"],
    "油饼": ["fried dough pancake chinese", "youbing chinese"],
    "糖饼": ["sweet pancake chinese filled"],
    "韭菜盒子": ["chive pocket chinese pan cake"],
    "馅饼": ["chinese stuffed pancake pie"],
    "饺子": ["chinese dumplings jiaozi pork"],
    "水饺": ["boiled chinese dumplings jiaozi"],
    "煎饺": ["pan fried dumplings gyoza"],
    "蒸饺": ["steamed chinese dumplings"],
    "锅贴": ["potstickers chinese pan fried dumpling"],
    "元宝饺子": ["boat dumplings chinese", "gold ingot dumplings"],
    "韭菜鸡蛋饺子": ["chive egg dumplings chinese"],
    "白菜猪肉饺子": ["cabbage pork dumplings chinese"],
    "羊肉饺子": ["lamb dumplings chinese"],
    "芹菜猪肉饺子": ["celery pork dumplings chinese"],
    "三鲜饺子": ["three fresh dumplings chinese shrimp egg"],
    "豆腐饺子": ["tofu dumplings chinese"],
    "酸菜猪肉饺子": ["sour cabbage pork dumplings chinese"],
    "猪肉白菜饺子": ["pork cabbage dumplings chinese"],
    "香菇猪肉饺子": ["shiitake pork dumplings chinese"],
    "饺子": ["chinese dumplings jiaozi pork"],
    "包子": ["steamed pork buns baozi"],
    "肉包子": ["steamed pork baozi bun chinese"],
    "小笼包": ["shanghai xiaolongbao soup dumpling"],
    "生煎包": ["shengjian pan fried pork bun"],
    "菜包子": ["vegetable baozi bun chinese"],
    "豆沙包": ["red bean paste baozi chinese sweet"],
    "红糖馒头": ["brown sugar steamed bun chinese"],
    "花卷": ["flower roll steamed bread chinese"],
    "发糕": ["sweet steamed cake chinese"],
    "玉米发糕": ["corn steamed cake chinese"],
    "红糖发糕": ["brown sugar steamed cake chinese"],
    "小米粥": ["millet porridge chinese breakfast"],
    "皮蛋瘦肉粥": ["century egg lean pork congee"],
    "白粥": ["plain chinese congee"],
    "南瓜粥": ["pumpkin porridge chinese"],
    "小米南瓜粥": ["millet pumpkin porridge chinese"],
    "紫米粥": ["purple rice porridge chinese"],
    "八宝粥": ["eight treasure porridge chinese"],
    "绿豆粥": ["mung bean porridge chinese"],
    "玉米粥": ["corn porridge chinese"],
    "皮蛋粥": ["century egg porridge chinese"],
    "虾粥": ["shrimp congee chinese"],
    "海鲜粥": ["seafood congee chinese"],
    "鱼片粥": ["fish slice congee chinese"],
    "牛肉粥": ["beef congee chinese"],
    "排骨粥": ["pork ribs congee chinese"],
    "鸡肉粥": ["chicken congee chinese"],
    "蛋花汤": ["egg drop soup chinese"],
    "紫菜蛋花汤": ["seaweed egg drop soup chinese"],
    "番茄蛋汤": ["tomato egg drop soup chinese"],
    "西红柿鸡蛋汤": ["tomato egg soup chinese"],
    "豆腐汤": ["tofu soup chinese"],
    "白菜豆腐汤": ["napa cabbage tofu soup chinese"],
    "西红柿豆腐汤": ["tomato tofu soup chinese"],
    "酸辣汤": ["hot and sour soup chinese"],
    "冬瓜汤": ["winter melon soup chinese"],
    "丝瓜汤": ["loofah soup chinese"],
    "紫菜汤": ["seaweed soup chinese"],
    "海带汤": ["kelp soup chinese"],
    "番茄汤": ["tomato soup chinese"],
    "西红柿汤": ["tomato soup chinese"],
    "蛋花汤": ["egg drop soup chinese"],
    "萝卜排骨汤": ["radish pork ribs soup chinese"],
    "冬瓜排骨汤": ["winter melon pork ribs soup chinese"],
    "海带排骨汤": ["kelp pork ribs soup chinese"],
    "玉米排骨汤": ["corn pork ribs soup chinese"],
    "莲藕排骨汤": ["lotus root pork ribs soup chinese"],
    "山药排骨汤": ["chinese yam pork ribs soup"],
    "西红柿排骨汤": ["tomato pork ribs soup chinese"],
    "萝卜炖牛腩": ["radish beef brisket stew chinese"],
    "牛腩煲": ["beef brisket hotpot chinese"],
    "番茄牛腩": ["tomato beef brisket chinese"],
    "红烧牛腩": ["braised beef brisket chinese soy"],
    "土豆炖牛腩": ["braised beef potato chinese"],
    "白切鸡": ["white cut chicken cantonese"],
    "盐焗鸡": ["salt baked chicken chinese"],
    "白切鸡": ["white cut chicken cantonese"],
    "三杯鸡": ["three cup chicken taiwanese"],
    "黄焖鸡": ["braised chicken chinese"],
    "咖喱鸡": ["curry chicken asian"],
    "红烧鸡块": ["braised chicken chunks chinese"],
    "香菇滑鸡": ["shiitake chicken chinese"],
    "小鸡炖蘑菇": ["chicken mushroom stew chinese"],
    "土豆炖鸡": ["potato chicken stew chinese"],
    "小鸡炖蘑菇": ["chicken mushroom stew chinese"],
    "咖喱鸡肉": ["curry chicken asian"],
    "葱油鸡": ["scallion oil chicken chinese"],
    "豉油鸡": ["soy sauce chicken cantonese", "soy poached chicken chinese"],
    "盐焗鸡": ["salt baked chicken chinese"],
    "盐焗鸡爪": ["salt baked chicken feet chinese"],
    "盐焗鸡腿": ["salt baked chicken leg chinese"],
    "奥尔良鸡翅": ["orleans chicken wings chinese"],
    "糖醋鸡翅": ["sweet and sour chicken wings chinese"],
    "可乐鸡翅": ["cola braised chicken wings chinese"],
    "啤酒鸭": ["beer duck chinese braised"],
    "红烧鸭子": ["braised duck chinese soy"],
    "啤酒鸭": ["beer duck chinese braised"],
    "盐水鸭": ["salt water duck cantonese"],
    "酱鸭": ["soy braised duck chinese"],
    "鸭子炖土豆": ["duck potato stew chinese"],
    "啤酒鸭": ["beer duck chinese braised"],
    "烤鸭": ["peking duck chinese roast duck"],
    "北京烤鸭": ["peking duck chinese roast duck"],
    "脆皮烧鸭": ["crispy roast duck chinese bbq"],
    "烧鸭": ["char siu roasted duck chinese bbq"],
    "蜜汁叉烧": ["sweet braised pork chinese bbq"],
    "烧肉": ["bbq pork chinese char siu"],
    "叉烧肉": ["sweet braised pork bbq chinese"],
    "烧鸭腿": ["roast duck leg chinese bbq"],
    "卤鸭": ["braised duck chinese soy"],
    "卤肉": ["braised pork chinese soy soybean", "lu rou chinese"],
    "卤蛋": ["braised egg chinese soy"],
    "卤鸡蛋": ["braised egg chinese soy"],
    "茶叶蛋": ["chinese tea egg marbled soy"],
    "卤牛腱": ["braised beef shank chinese soy"],
    "卤牛肉": ["braised beef chinese soy"],
    "卤猪蹄": ["braised pig trotter chinese soy"],
    "卤鸡爪": ["braised chicken feet chinese soy"],
    "卤肉饭": ["braised pork rice taiwanese", "lu rou fan chinese"],
    "红烧猪蹄": ["braised pig trotter chinese soy"],
    "黄豆炖猪蹄": ["soybean pig trotter stew chinese"],
    "猪脚姜": ["pig trotter ginger cantonese"],
    "红烧猪手": ["braised pig trotter chinese soy"],
    "糖醋排骨": ["sweet and sour pork ribs chinese"],
    "红烧排骨": ["braised pork ribs chinese"],
    "蒜香排骨": ["garlic pork ribs chinese baked"],
    "椒盐排骨": ["salt and pepper pork ribs chinese fried"],
    "糖醋小排": ["sweet and sour pork ribs chinese"],
    "粉蒸排骨": ["steamed pork ribs with rice flour chinese"],
    "芋头蒸排骨": ["taro steamed pork ribs chinese"],
    "莲藕蒸排骨": ["lotus root steamed pork ribs chinese"],
    "玉米蒸排骨": ["corn steamed pork ribs chinese"],
    "土豆蒸排骨": ["potato steamed pork ribs chinese"],
    "排骨蒸饭": ["steamed rice with pork ribs chinese"],
    "蛋炒饭": ["chinese egg fried rice"],
    "酱油炒饭": ["soy sauce fried rice chinese"],
    "扬州炒饭": ["yangzhou fried rice chinese"],
    "牛肉炒饭": ["beef fried rice chinese"],
    "火腿炒饭": ["ham fried rice chinese"],
    "咖喱炒饭": ["curry fried rice chinese"],
    "蛋炒饭": ["chinese egg fried rice"],
    "什锦炒饭": ["mixed fried rice chinese"],
    "海鲜炒饭": ["seafood fried rice chinese"],
    "虾仁炒饭": ["shrimp fried rice chinese"],
    "腊肠炒饭": ["lap cheong fried rice chinese", "cantonese sausage fried rice"],
    "腊味合蒸": ["cantonese dried meat steam", "la wei he zheng cantonese"],
    "炒饭": ["chinese fried rice"],
    "蛋炒饭": ["chinese egg fried rice"],
    "扬州炒饭": ["yangzhou fried rice chinese"],
    "西红柿炒鸡蛋": ["tomato scrambled egg chinese"],
    "番茄炒鸡蛋": ["tomato scrambled egg chinese"],
    "番茄炒蛋": ["tomato scrambled egg chinese", "tomato egg stir fry"],
    "西红柿炒鸡蛋": ["tomato scrambled egg chinese"],
    "醋溜白菜": ["napa cabbage chinese stir fry vinegar"],
    "醋溜土豆丝": ["shredded potato chinese stir fry vinegar", "sour and crispy shredded potato"],
    "酸辣土豆丝": ["sour spicy shredded potato chinese"],
    "糖醋里脊": ["sweet and sour pork tenderloin chinese"],
    "咕咾肉": ["sweet and sour pork chinese"],
    "锅包肉": ["guo bao rou jilin sweet sour pork"],
    "锅包肉": ["guo bao rou jilin sweet sour pork"],
    "粉蒸肉": ["steamed pork with rice flour chinese"],
    "梅菜扣肉": ["braised pork with preserved vegetable chinese"],
    "东坡肉": ["dongpo pork chinese"],
    "红烧肉": ["braised pork belly chinese soy sauce"],
    "扣肉": ["braised pork slice chinese"],
    "梅菜扣肉": ["braised pork with preserved vegetable chinese"],
    "白切肉": ["white cut pork chinese", "boiled pork chinese"],
    "凉拌菜": ["chinese cold dish salad"],
    "凉拌黄瓜": ["chinese cold cucumber salad"],
    "凉拌豆腐": ["chinese cold tofu salad"],
    "凉拌木耳": ["chinese cold wood ear mushroom salad"],
    "凉拌猪耳": ["chinese cold pig ear salad"],
    "皮蛋豆腐": ["century egg tofu chinese"],
    "皮蛋豆腐凉菜": ["century egg tofu chinese cold"],
    "蒜泥茄子": ["garlic mashed eggplant chinese"],
    "蒜泥白肉": ["garlic cold pork chinese sliced"],
    "口水鸡": ["口水鸡 sichuan chili chicken", "mouth water chicken sichuan"],
    "凉拌鸡丝": ["chinese cold shredded chicken salad"],
    "凉拌海蜇": ["chinese cold jellyfish salad"],
    "麻辣鸡丝": ["spicy shredded chicken chinese"],
    "凉拌三丝": ["chinese cold three shredded threads salad"],
    "糖拌西红柿": ["sugar tomato chinese cold dish"],
    "凉拌西红柿": ["chinese cold tomato salad"],
    "糖拌西红柿": ["sugar tomato chinese cold dish"],
    "拍黄瓜": ["chinese smashed cucumber salad"],
    "凉拌黄瓜": ["chinese cold cucumber salad"],
    "拍黄瓜": ["chinese smashed cucumber salad"],
    "凉拌土豆丝": ["chinese cold shredded potato salad"],
    "凉拌海带丝": ["chinese cold kelp salad"],
    "凉拌豆皮": ["chinese cold bean skin salad"],
    "凉拌藕片": ["chinese cold lotus root salad"],
    "凉拌苦瓜": ["chinese cold bitter gourd salad"],
    "凉拌萝卜": ["chinese cold radish salad"],
    "凉拌萝卜丝": ["chinese cold shredded radish salad"],
    "凉拌豆芽": ["chinese cold bean sprout salad"],
    "皮蛋豆腐": ["century egg tofu chinese cold"],
    "凉拌皮蛋": ["chinese cold century egg salad"],
    "糖拌西红柿": ["sugar tomato chinese cold dish"],
    "红烧鲤鱼": ["braised carp chinese soy sauce"],
    "红烧鲫鱼": ["braised crucian fish chinese soy"],
    "清蒸鲈鱼": ["steamed sea bass chinese soy ginger"],
    "清蒸鳜鱼": ["steamed mandarin fish chinese soy"],
    "干烧鱼": ["dry braised fish chinese"],
    "糖醋鲤鱼": ["sweet and sour carp chinese"],
    "红烧带鱼": ["braised hairtail fish chinese soy sauce"],
    "红烧鳕鱼": ["braised cod fish chinese"],
    "红烧黄鱼": ["braised yellow croaker chinese soy"],
    "红烧鲈鱼": ["braised sea bass chinese soy"],
    "糖醋带鱼": ["sweet and sour hairtail chinese"],
    "酸菜鱼": ["sour pickled vegetable fish chinese"],
    "水煮鱼": ["boiled fish fillet sichuan spicy"],
    "剁椒鱼头": ["chopped chili fish head hunan"],
    "红烧鱼": ["braised fish chinese soy sauce"],
    "清蒸鱼": ["steamed whole fish cantonese ginger soy"],
    "糖醋鱼": ["sweet and sour fish chinese"],
    "干烧鱼": ["dry braised fish chinese"],
    "红烧鲤鱼": ["braised carp chinese soy sauce"],
    "红烧鲫鱼": ["braised crucian fish chinese soy"],
    "糖醋鲤鱼": ["sweet and sour carp chinese"],
    "蒜蓉粉丝蒸扇贝": ["garlic glass noodle steamed scallop"],
    "蒜蓉粉丝蒸虾": ["garlic glass noodle steamed prawn chinese"],
    "蒜蓉烤生蚝": ["garlic roasted oyster chinese"],
    "蒜蓉烤扇贝": ["garlic roasted scallop chinese"],
    "黄油烤大虾": ["butter roasted prawn chinese"],
    "黄油蒜蓉虾": ["butter garlic prawn chinese"],
    "白灼虾": ["boiled shrimp chinese soy sauce dip"],
    "油焖大虾": ["braised prawns chinese soy sauce"],
    "糖醋大虾": ["sweet and sour prawn chinese"],
    "椒盐大虾": ["salt and pepper prawn chinese"],
    "盐水虾": ["salt water shrimp chinese"],
    "红烧虾": ["braised prawn chinese soy sauce"],
    "清蒸虾": ["steamed prawn chinese"],
    "蒜蓉蒸虾": ["garlic steamed prawn chinese"],
    "红烧蟹": ["braised crab chinese soy sauce"],
    "清蒸蟹": ["steamed crab chinese"],
    "姜葱炒蟹": ["ginger scallion crab chinese stir fry"],
    "姜葱炒蟹": ["ginger scallion crab chinese stir fry"],
    "葱姜炒蟹": ["scallion ginger crab chinese stir fry"],
    "清蒸大闸蟹": ["steamed hairy crab chinese soy sauce ginger"],
    "清蒸大闸蟹": ["steamed hairy crab chinese soy sauce ginger"],
    "盐水虾": ["salt water shrimp chinese"],
    "油爆虾": ["fried shrimp chinese wok"],
    "红烧小龙虾": ["braised crayfish chinese spicy", "crayfish chinese spicy"],
    "麻辣小龙虾": ["spicy crayfish chinese sichuan", "crayfish sichuan spicy"],
    "蒜蓉小龙虾": ["garlic crayfish chinese"],
    "十三香小龙虾": ["thirteen spice crayfish chinese"],
    "十三香小龙虾": ["thirteen spice crayfish chinese"],
    "啤酒虾": ["beer shrimp chinese"],
    "香辣虾": ["spicy shrimp chinese"],
    "香辣蟹": ["spicy crab chinese"],
    "香辣蟹": ["spicy crab chinese"],
    "咖喱蟹": ["curry crab chinese"],
    "咖喱虾": ["curry shrimp chinese"],
    "咸蛋黄蟹": ["salted egg yolk crab chinese"],
    "清蒸大闸蟹": ["steamed hairy crab chinese soy sauce ginger"],
    "清蒸小龙虾": ["steamed crayfish chinese"],
    "蒜蓉蒸龙虾": ["garlic steamed lobster chinese"],
    "蒜蓉蒸扇贝": ["garlic steamed scallop chinese"],
    "蒜蓉粉丝蒸扇贝": ["garlic glass noodle steamed scallop chinese"],
    "红烧肉": ["braised pork belly chinese soy sauce"],
    "梅菜扣肉": ["braised pork with preserved vegetable chinese"],
    "红烧肉炖土豆": ["braised pork potato chinese"],
    "红烧肉炖萝卜": ["braised pork radish chinese"],
    "红烧肉炖鹌鹑蛋": ["braised pork quail egg chinese"],
    "红烧肉炖竹笋": ["braised pork bamboo shoot chinese"],
    "红烧肉炖豆腐": ["braised pork tofu chinese"],
    "红烧肉炖香菇": ["braised pork mushroom chinese"],
    "粉蒸肉": ["steamed pork with rice flour chinese"],
    "梅菜扣肉": ["braised pork with preserved vegetable chinese"],
    "扣肉": ["braised pork slice chinese"],
    "东坡肉": ["dongpo pork chinese"],
    "把子肉": ["bazi meat chinese soy sauce pork"],
    "红烧肉": ["braised pork belly chinese soy sauce"],
    "白切肉": ["white cut pork chinese boiled"],
    "白切肉": ["white cut pork chinese boiled"],
    "蒜泥白肉": ["garlic cold pork chinese sliced"],
    "蒜泥白肉": ["garlic cold pork chinese sliced"],
    "凉拌猪耳": ["chinese cold pig ear salad"],
    "凉拌猪耳": ["chinese cold pig ear salad"],
    "凉拌猪肚": ["chinese cold pig stomach salad"],
    "凉拌鸡丝": ["chinese cold shredded chicken salad"],
    "凉拌鸡丝": ["chinese cold shredded chicken salad"],
    "口水鸡": ["口水鸡 sichuan chili chicken"],
    "口水鸡": ["口水鸡 sichuan chili chicken"],
    "麻辣鸡丝": ["spicy shredded chicken chinese"],
    "麻辣鸡丝": ["spicy shredded chicken chinese"],
    "凉拌鸡丝": ["chinese cold shredded chicken salad"],
    "凉拌皮蛋": ["chinese cold century egg salad"],
    "凉拌皮蛋": ["chinese cold century egg salad"],
    "糖拌西红柿": ["sugar tomato chinese cold dish"],
    "糖拌西红柿": ["sugar tomato chinese cold dish"],
    "凉拌西红柿": ["chinese cold tomato salad"],
    "凉拌西红柿": ["chinese cold tomato salad"],
    "糖拌西红柿": ["sugar tomato chinese cold dish"],
    "皮蛋豆腐": ["century egg tofu chinese cold"],
    "皮蛋豆腐": ["century egg tofu chinese cold"],
    "糖拌西红柿": ["sugar tomato chinese cold dish"],
    "糖拌西红柿": ["sugar tomato chinese cold dish"],
    "凉拌黄瓜": ["chinese cold cucumber salad"],
    "拍黄瓜": ["chinese smashed cucumber salad"],
    "拍黄瓜": ["chinese smashed cucumber salad"],
    "凉拌黄瓜": ["chinese cold cucumber salad"],
    "糖拌西红柿": ["sugar tomato chinese cold dish"],
    "糖拌西红柿": ["sugar tomato chinese cold dish"],
    "凉拌西红柿": ["chinese cold tomato salad"],
    "凉拌西红柿": ["chinese cold tomato salad"],
    "凉拌土豆丝": ["chinese cold shredded potato salad"],
    "凉拌土豆丝": ["chinese cold shredded potato salad"],
    "凉拌海带丝": ["chinese cold kelp salad"],
    "凉拌海带丝": ["chinese cold kelp salad"],
    "凉拌萝卜丝": ["chinese cold shredded radish salad"],
    "凉拌萝卜丝": ["chinese cold shredded radish salad"],
    "凉拌豆芽": ["chinese cold bean sprout salad"],
    "凉拌豆芽": ["chinese cold bean sprout salad"],
    "凉拌藕片": ["chinese cold lotus root salad"],
    "凉拌藕片": ["chinese cold lotus root salad"],
    "凉拌苦瓜": ["chinese cold bitter gourd salad"],
    "凉拌苦瓜": ["chinese cold bitter gourd salad"],
    "凉拌三丝": ["chinese cold three shredded threads salad"],
    "凉拌三丝": ["chinese cold three shredded threads salad"],
    "凉拌豆腐": ["chinese cold tofu salad"],
    "凉拌豆腐": ["chinese cold tofu salad"],
    "凉拌木耳": ["chinese cold wood ear mushroom salad"],
    "凉拌木耳": ["chinese cold wood ear mushroom salad"],
    "凉拌菜心": ["chinese cold chinese broccoli salad"],
    "凉拌菜心": ["chinese cold chinese broccoli salad"],
    "凉拌时蔬": ["chinese cold seasonal vegetables salad"],
    "凉拌时蔬": ["chinese cold seasonal vegetables salad"],
    "凉拌海带结": ["chinese cold kelp knot salad"],
    "凉拌海带结": ["chinese cold kelp knot salad"],
    "凉拌腐竹": ["chinese cold dried bean curd salad"],
    "凉拌腐竹": ["chinese cold dried bean curd salad"],
    "凉拌豆皮": ["chinese cold bean skin salad"],
    "凉拌豆皮": ["chinese cold bean skin salad"],
    "凉拌花生米": ["chinese cold peanut salad"],
    "凉拌花生米": ["chinese cold peanut salad"],
    "凉拌腐竹": ["chinese cold dried bean curd salad"],
    "凉拌腐竹": ["chinese cold dried bean curd salad"],
    "凉拌豆皮": ["chinese cold bean skin salad"],
    "凉拌豆皮": ["chinese cold bean skin salad"],
}

# 英文词 → 中文反向映射（供英→中方向，如用户输入英文搜索词时给出中文提示）
EN_TO_ZH = {}
for zh_words, ens in DISH_EN.items():
    for en in ens:
        for w in en.split():
            if w not in EN_TO_ZH:
                EN_TO_ZH[w] = zh_words
for zh, en in WORD_EN.items():
    for w in en.split():
        if w not in EN_TO_ZH:
            EN_TO_ZH[w] = zh


def _mymemory_query(text: str) -> Optional[str]:
    try:
        conn = sqlite3.connect(DATABASE_PATH, check_same_thread=False)
        cached = conn.execute("SELECT result FROM translations WHERE key = ?", (hashlib.sha1((text + " en-zh-search").encode("utf-8")).hexdigest(),)).fetchone()
        conn.close()
        if cached:
            return cached[0]
    except Exception:
        pass
    q = urllib.parse.urlencode({"q": text, "langpair": _LANGPAIR})
    url = f"{MYMEMORY_URL}?{q}"
    req = urllib.request.Request(url, headers={"User-Agent": "what-to-eat-today/1.0"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode("utf-8", errors="ignore"))
    out = ((data or {}).get("responseData") or {}).get("translatedText")
    if out and "@@QUALITY@@" in str(out):
        out = str(out).split("@@QUALITY@@")[0].strip()
    return out or None


def _translate_keyword_to_en(kw: str, proxy_url: str = "") -> tuple:
    """
    中文/英文 关键词 ↔ TheMealDB 检索词。
    策略：
    1. 纯英文：返回原词 + 反向词典给出的中文提示
    2. 中文：DISH_EN 精确整菜名匹配 → WORD_EN 词级替换 → MyMemory 兜底
    3. 中英混：走中文逻辑
    返回 (is_chinese, zh_display, en_candidates)
    """
    kw = (kw or "").strip()
    if not kw:
        return False, "", []

    has_zh = _is_chinese(kw)
    has_en = bool(re.search(r"[A-Za-z]", kw))
    en_candidates = []
    seen = set()

    def add(q: str):
        q = " ".join(q.split())
        if not q or q.lower() in seen:
            return
        seen.add(q.lower())
        en_candidates.append(q)

    if not has_zh and has_en:
        add(kw)
        zh_hint = _en_to_zh_hint(kw)
        return False, zh_hint or kw, en_candidates[:3]

    # ---- 中文处理 ----
    # 1) 整菜名精确匹配（长词优先）
    tmp = kw
    for zh in sorted(set(DISH_EN.keys()) | set(_DISH_EN_ADDON.keys()), key=len, reverse=True):
        if zh in tmp:
            tmp = tmp.replace(zh, " ")
            for d in (DISH_EN.get(zh) or []) + (_DISH_EN_ADDON.get(zh) or []):
                add(d)
            if len(en_candidates) >= 5:
                return True, kw, en_candidates[:5]

    # 2) 词级替换
    replaced = kw
    for zh, en in sorted(WORD_EN.items(), key=lambda kv: len(kv[0]), reverse=True):
        replaced = replaced.replace(zh, " " + en + " ")
    tokens = [w for w in replaced.split() if not _is_chinese(w)]
    head = " ".join(tokens)
    if head:
        add(head)
        add(head + " chinese dish")
        add(head + " chinese food")
        if len(en_candidates) >= 3:
            return True, kw, en_candidates[:5]

    # 3) 后缀兜底
    for tail in [
        "chinese food dish recipe",
        "chinese cooking asian food",
        "asian stir fry plate meal",
    ]:
        add(kw + " " + tail)

    # 4) MyMemory 兜底
    try:
        out = _mymemory_query(kw)
        if out:
            add(out)
            add(out + " chinese dish")
    except Exception:
        pass

    return True, kw, en_candidates[:5]


def _en_to_zh_hint(kw: str) -> Optional[str]:
    words = set(re.findall(r"[A-Za-z]{3,}", kw.lower()))
    zh_hits = [EN_TO_ZH[w] for w in words if w in EN_TO_ZH]
    if not zh_hits:
        return None
    zh_hits.sort()
    return "、".join(list(dict.fromkeys(zh_hits))[:4])


def _fetch_json(url: str, proxy_url: str = ""):
    req = urllib.request.Request(url, headers={"User-Agent": "what-to-eat-today/1.0", "Accept": "application/json"})
    opener = _make_http_opener(proxy_url)
    if opener is None:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode("utf-8"))
    with opener.open(req, timeout=15) as resp:
        return json.loads(resp.read().decode("utf-8"))


# ---------- TheMealDB 搜索 ----------

def _split_steps(text: Optional[str]) -> List[str]:
    if not text:
        return []
    parts = [p.strip() for p in re.split(r"\r?\n", text) if p.strip()]
    if len(parts) <= 1:
        parts = [p.strip() for p in re.split(r"(?<=[.!?。])\s+", text) if p.strip()]
    steps = []
    for p in parts:
        p = re.sub(r"^STEP\s*\d+\s*[:\-\.]?\s*", "", p, flags=re.IGNORECASE).strip()
        p = re.sub(r"^\d+[\.\)、]\s*", "", p).strip()
        if p and not p.lower().startswith("step "):
            steps.append(p)
    return steps


def _normalize_meal(m: dict) -> dict:
    ingredients = []
    for i in range(1, 21):
        name = (m.get(f"strIngredient{i}") or "").strip()
        if not name:
            continue
        amount = (m.get(f"strMeasure{i}") or "").strip()
        ingredients.append({"name": name, "amount": amount})
    return {
        "id": str(m.get("idMeal") or ""),
        "title": (m.get("strMeal") or "").strip(),
        "category": (m.get("strCategory") or "").strip(),
        "area": (m.get("strArea") or "").strip(),
        "tags": (m.get("strTags") or "").strip(),
        "thumb": (m.get("strMealThumb") or "").strip(),
        "source": "themealdb",
        "ingredients": ingredients,
        "steps": _split_steps(m.get("strInstructions")),
    }


@router.get("/search")
def search_recipes(
    keyword: str,
    conn: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    """搜索 TheMealDB 菜谱。中文关键词先用内置词典转英文召回。"""
    proxy_url = (get_setting("proxy_url", "", conn=conn) or "").strip()
    kw = (keyword or "").strip()
    if not kw:
        return []
    is_zh, zh_disp, en_queries = _translate_keyword_to_en(kw, proxy_url)
    terms: List[str] = []
    seen: set = set()
    for q in en_queries:
        for t in [q] + [w for w in re.split(r"\s+", q) if len(w) >= 3]:
            t = t.strip()
            if t and t.lower() not in seen:
                seen.add(t.lower())
                terms.append(t)
    terms = terms[:10]

    meals: dict = {}
    last_err = None
    for t in terms:
        try:
            url = f"{THEMEALDB_ENDPOINT}/search.php?s={urllib.parse.quote(t)}"
            data = _fetch_json(url, proxy_url)
            for m in (data.get("meals") or []):
                mid = str(m.get("idMeal") or "")
                if mid and mid not in meals:
                    meals[mid] = _normalize_meal(m)
        except Exception as e:
            last_err = f"{type(e).__name__}: {e}"
            print(f"[recipe-api] search kw={kw!r} term={t!r} FAIL {last_err}", flush=True)
            continue
    out = list(meals.values())
    print(f"[recipe-api] search kw={kw!r} terms={terms!r} hit={len(out)} last_err={last_err}", flush=True)
    return {
        "items": out,
        "zh_keyword": zh_disp if is_zh else "",
        "en_queries": [t for t in terms if not _is_chinese(t)],
    }


@router.get("/translate-keyword")
def translate_keyword(
    keyword: str,
    conn: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    """中英互换：内置词典精确匹配优先，MyMemory 仅兜底。

    返回 is_chinese / zh / en 三字段，前端用于：
    - 中文输入 → 给出英文候选填入搜索框
    - 英文输入 → 给出中文候选提示
    """
    kw = (keyword or "").strip()
    if not kw:
        return {"is_chinese": False, "zh": "", "en": []}
    is_zh, zh_disp, en_out = _translate_keyword_to_en(kw, (get_setting("proxy_url", "", conn=conn) or "").strip())
    return {"is_chinese": is_zh, "zh": zh_disp, "en": en_out}


# ---------- 英转中 prepare ----------

class IngredientItem(BaseModel):
    name: str = ""
    amount: str = ""


class RecipeImportBody(BaseModel):
    id: Optional[str] = None
    title: str = ""
    category: Optional[str] = None
    area: Optional[str] = None
    thumb: Optional[str] = None
    ingredients: List[IngredientItem] = []
    steps: List[str] = []
    translate: Optional[int] = None  # 1=开 0=关；缺省用系统设置 recipe_translate


_DESSERT_HINTS = ("dessert", "cake", "pie", "cookie", "sweet", "pudding", "muffin")


@router.post("/prepare")
def prepare_import(
    body: RecipeImportBody,
    conn: sqlite3.Connection = Depends(get_db),
    user=Depends(get_current_user),
):
    """把 TheMealDB 菜谱做英转中，返回可直接填充表单的结构（可再编辑）。"""
    if body.translate is not None:
        do_translate = bool(body.translate)
    else:
        do_translate = (get_setting("recipe_translate", "1", conn=conn) or "1") == "1"

    def _zh(text: str) -> str:
        if do_translate and _has_latin(text):
            return translate_text(text)
        return text

    title_zh = _zh(body.title or "")

    def _ing_zh(ing: IngredientItem):
        if do_translate and _has_latin(ing.name):
            n, a = translate_ingredient(ing.name, ing.amount)
        else:
            n, a = ing.name, ing.amount
        amt, unit = split_amount_unit(a)
        return {"name": n, "amount": amt, "unit": unit}

    # MyMemory 单次较慢（1~2s），用线程池并行翻译食材/步骤，显著缩短等待
    with cf.ThreadPoolExecutor(max_workers=8) as pool:
        ingredients_zh = list(pool.map(_ing_zh, body.ingredients))
        steps_zh = list(pool.map(_zh, body.steps))

    category = ""
    cat_low = (body.category or "").lower()
    if any(h in cat_low for h in _DESSERT_HINTS):
        category = "甜点"

    payload = {
        "title": title_zh,
        "category": category,
        "image_path": (body.thumb or "").strip(),
        "servings": 2,
        "meal_tags": ["lunch", "dinner"],
        "ingredients": ingredients_zh,
        "steps": [{"description": s} for s in steps_zh],
        "prep_time": None,
        "cook_time": None,
        "source": "themealdb",
        "source_id": (body.id or "").strip(),
        "source_url": f"https://www.themealdb.com/meal/{(body.id or '').strip()}",
        "original_title": (body.title or "").strip() if do_translate else "",
    }
    return payload


# ---------- 粘贴解析 ----------

class PasteBody(BaseModel):
    text: str = ""


_ING_MARKERS = ("食材", "材料", "原料", "配料", "用料", "所需材料", "ingredient", "你需要")
_STEP_MARKERS = ("做法", "步骤", "制作方法", "烹饪步骤", "制作过程", "操作步骤", "做法步骤",
                 "instructions", "method", "directions", "direction", "process", "preparation",
                 "how to", "cooking steps", "步骤做法")


def _is_step_line(ln: str) -> bool:
    low = ln.lower().strip()
    return any(mk in low for mk in _STEP_MARKERS)


def _is_ing_section_line(ln: str) -> bool:
    """判断一行是不是「食材」小节标题：取前 12 个字符判断，避免命中句中单词。"""
    low = ln.strip().lower()[:12]
    return any(mk in low for mk in _ING_MARKERS)


_UNIT_CHARS = r"a-zA-Z\u5ea6\u514b\u65a4\u4e24\u52fa\u676f\u7897\u6beb\u5347\u4e2a\u679a\u53ea\u6839\u7247\u5c0f\u5927\u534agGkgml"
_QUALIFIERS = ("适量", "少许", "若干", "少量", "足量", "一把", "两把",
               "to taste", "a pinch", "pinch", "dash", "little", "some")
_NUM = r"(?:\d+\s*\d+/\d+|\d+/\d+|\d+(?:\.\d+)?)"


def _split_one_ingredient(it: str) -> dict:
    """拆单条食材为 {name, amount, unit}。
    兼容 'salt 1 tsp' / 'eggs 4' / '鸡蛋2个' / '4 eggs' / '2 tbsp oil' / '3个番茄' / '葱花适量' / '1/2 tsp'。
    """
    it = it.strip().lstrip("：:")
    if not it:
        return None
    U = _UNIT_CHARS
    UGROUP = r"(?:\s*[" + U + r"]+)*"
    NT = "(" + _NUM + r")"
    # 1) 名称在前，数量含单位在后（空格分隔）：salt 1 tsp / 盐 1小勺
    m = re.match(r"^(.+?)\s+(" + _NUM + UGROUP + r")\s*$", it)
    if m and m.group(1).strip():
        n2, u2 = split_amount_unit(m.group(2).strip())
        return {"name": m.group(1).strip(), "amount": n2, "unit": u2}
    # 2) 名称 + 裸数字：eggs 4
    m = re.match(r"^(.+?)\s+" + NT + r"\s*$", it)
    if m and m.group(1).strip():
        return {"name": m.group(1).strip(), "amount": m.group(2).strip(), "unit": ""}
    # 3) 名称 + 附着单位数字：鸡蛋2个 / 盐1勺
    m = re.match(r"^(.+?)(" + _NUM + r"\s*[" + U + r"]+)\s*$", it)
    if m and m.group(1).strip():
        n2, u2 = split_amount_unit(m.group(2).strip())
        return {"name": m.group(1).strip(), "amount": n2, "unit": u2}
    # 4) 数量在前（可带单位词）再跟名称：4 eggs / 2 tbsp oil / 500克 五花肉
    m = re.match(r"^(" + _NUM + UGROUP + r")\s+(.+)$", it)
    if m and m.group(2).strip():
        n2, u2 = split_amount_unit(m.group(1).strip())
        return {"name": m.group(2).strip(), "amount": n2, "unit": u2}
    # 5) 数量+单位紧贴再跟名称：3个番茄
    m = re.match(r"^(" + _NUM + r"\s*[" + U + r"]+)\s*(.+)$", it)
    if m and m.group(2).strip():
        n2, u2 = split_amount_unit(m.group(1).strip())
        return {"name": m.group(2).strip(), "amount": n2, "unit": u2}
    # 6) 定性用量：葱花适量 → 葱花 / 适量
    for q in _QUALIFIERS:
        if it.rstrip().endswith(q):
            nm = it[: -len(q)].rstrip(" :：")
            if nm:
                return {"name": nm, "amount": q, "unit": ""}
    return {"name": it, "amount": "", "unit": ""}


def _split_ingredient_line(line: str):
    """一行可能含多个食材（逗号/顿号分隔）：逐个拆出 {name, amount}。"""
    items = [x.strip() for x in re.split(r"[,，、;；]", line) if x.strip()]
    outs = []
    for it in items:
        r = _split_one_ingredient(it)
        if r:
            outs.append(r)
    return outs


def _parse_paste_text(text: str) -> dict:
    lines = [l.strip() for l in re.split(r"\r?\n", text) if l.strip()]
    if not lines:
        return {"title": "", "ingredients": [], "steps": []}
    title = lines[0].rstrip("。.")
    ing_start = None
    ing_end = None
    step_start = None
    for i, ln in enumerate(lines):
        marker_line = re.sub(r"^[\s\d\.、:：]*", "", ln).strip()
        if ing_start is None and _is_ing_section_line(ln):
            ing_start = i
        if step_start is None and ing_start is not None and len(marker_line) <= 30 and _is_step_line(marker_line):
            step_start = i
            ing_end = i
    if ing_end is None and ing_start is not None:
        ing_end = step_start if step_start is not None else len(lines)
    if step_start is None:
        step_start = len(lines)

    ingredients = []
    if ing_start is not None:
        # 「食材：番茄3个 鸡蛋4个」这种标题和内容在同一行 → 解析冒号后的内容
        colon = re.split(r"[:：]", lines[ing_start], maxsplit=1)
        if len(colon) > 1 and colon[1].strip():
            ingredients.extend(_split_ingredient_line(colon[1].strip().lstrip(" :：")))
        for ln in lines[ing_start + 1:ing_end]:
            if not ln or _is_step_line(ln):
                continue
            ingredients.extend(_split_ingredient_line(ln))

    steps = []
    for ln in lines[step_start + 1:]:
        if not ln or any(mk in ln for mk in _ING_MARKERS):
            continue
        s = re.sub(r"^\d+\s*[\.\)、．]\s*", "", ln).strip()
        s = re.sub(r"^(步骤|step)\s*\d*\s*[:\-:]?\s*", "", s, flags=re.IGNORECASE).strip()
        s = re.sub(r"^[①②③④⑤⑥⑦⑧⑨⑩]\s*", "", s).strip()
        if s and not _is_step_line(s):
            steps.append(s)

    # 未识别到任何分节：数字行=食材，其余=步骤
    if not ingredients and not steps and len(lines) > 1:
        rest = lines[1:]
        num_lines = [ln for ln in rest if re.search(r"\d", ln)]
        ingredients = [{"name": ln, "amount": ""} for ln in num_lines]
        steps = [re.sub(r"^\d+[\.\)、．]\s*", "", ln).strip() for ln in rest if ln not in num_lines]

    return {"title": title, "ingredients": ingredients, "steps": steps}


@router.post("/parse-paste")
def parse_paste(
    body: PasteBody,
    user=Depends(get_current_user),
):
    """粘贴文本解析：标题 / 食材 / 步骤（中英文均可，尽力而为，前端可预览修改）。"""
    parsed = _parse_paste_text(body.text or "")
    return parsed