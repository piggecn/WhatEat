"""Pydantic 请求/响应模型。"""
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field


# ---- Auth ----
class LoginRequest(BaseModel):
    username: str
    password: str
    remember_me: bool = False  # 本地网络登录一次后免登录


class UserOut(BaseModel):
    id: int
    username: str
    display_name: Optional[str] = None
    is_admin: bool
    avatar: Optional[str] = None
    avatar_path: Optional[str] = None


class LoginResponse(BaseModel):
    token: str
    user: UserOut


class UserCreate(BaseModel):
    username: str = Field(min_length=1, max_length=50)
    display_name: Optional[str] = Field(None, max_length=50)
    avatar: Optional[str] = None
    password: str = Field(min_length=1, max_length=100)
    is_admin: bool = False


class UserProfileUpdate(BaseModel):
    """普通用户修改自己的资料：显示名 + 头像。"""
    display_name: str = Field(min_length=1, max_length=50)
    avatar: Optional[str] = None


class CarouselSettings(BaseModel):
    carousel_type: str = Field(default="most_cooked", pattern="^(most_cooked|favorites|recent|random)$")
    carousel_limit: int = Field(default=10, ge=5, le=20)


class ProfileSettingsOut(BaseModel):
    """GET /api/profile 的响应：含个人信息 + 轮播设置。"""
    id: int
    username: str
    display_name: Optional[str] = None
    avatar: Optional[str] = None
    is_admin: bool
    carousel_type: str
    carousel_limit: int


class ProfileUpdateIn(BaseModel):
    """PUT /api/profile 的请求体。"""
    display_name: str = Field(min_length=1, max_length=50)
    username: Optional[str] = Field(None, min_length=1, max_length=50)
    avatar: Optional[str] = None
    carousel_type: Optional[str] = Field(None, pattern="^(most_cooked|favorites|recent|random)$")
    carousel_limit: Optional[int] = Field(None, ge=5, le=20)


class PasswordChange(BaseModel):
    """修改自己的登录密码。"""
    old_password: str
    new_password: str = Field(min_length=1, max_length=100)


# ---- Recipe 子结构 ----
class IngredientIn(BaseModel):
    name: str
    amount: Optional[str] = None
    unit: Optional[str] = None


class StepIn(BaseModel):
    step_number: Optional[int] = None
    description: str


class RecipeCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: Optional[str] = None
    category: Optional[str] = None  # 早餐/午餐/晚餐/甜点/小吃/饮品（单分类）
    meal_tags: List[str] = Field(default_factory=list)  # ["breakfast","lunch","dinner"]
    servings: int = 2
    prep_time: Optional[int] = None
    cook_time: Optional[int] = None
    image_path: Optional[str] = None
    ingredients: list[IngredientIn] = []
    steps: list[StepIn] = []


class RecipeUpdate(RecipeCreate):
    """更新与创建结构一致；字段均可覆盖。"""


class IngredientOut(IngredientIn):
    id: int


class StepOut(StepIn):
    id: int


class RecipeDetail(BaseModel):
    id: int
    title: str
    description: Optional[str] = None
    category: Optional[str] = None
    meal_tags: List[str] = Field(default_factory=list)
    servings: int
    prep_time: Optional[int] = None
    cook_time: Optional[int] = None
    image_path: Optional[str] = None
    created_by: int
    author: str
    author_display_name: Optional[str] = None
    author_avatar: Optional[str] = None
    is_favorite: bool
    ingredients: list[IngredientOut] = []
    steps: list[StepOut] = []
    created_at: str
    updated_at: str
    total_eligible: Optional[int] = None  # 仅 random 接口使用
    empty: Optional[bool] = None
    message: Optional[str] = None


class RecipeListItem(BaseModel):
    id: int
    title: str
    description: Optional[str] = None
    category: Optional[str] = None
    meal_tags: List[str] = Field(default_factory=list)
    image_path: Optional[str] = None
    prep_time: Optional[int] = None
    cook_time: Optional[int] = None
    author: str
    author_display_name: Optional[str] = None
    author_avatar: Optional[str] = None
    is_favorite: bool
    created_at: str


class RecipeListResponse(BaseModel):
    total: int
    page: int
    page_size: int
    items: list[RecipeListItem]


# ---- Upload ----
class UploadResponse(BaseModel):
    path: str


# ---- User 管理 ----
class AdminUserOut(BaseModel):
    id: int
    username: str
    display_name: Optional[str] = None
    avatar: Optional[str] = None
    avatar_path: Optional[str] = None
    is_admin: bool
    created_at: str


# ---- 用餐记录 ----
class MealCreate(BaseModel):
    """记录一顿饭：关联食谱 + 类型 + 日期。"""
    recipe_id: int
    meal_type: str = Field(default="dinner", description="breakfast/lunch/dinner")
    date: str = Field(..., description="YYYY-MM-DD")


class MealResponse(BaseModel):
    id: int
    user_id: int
    recipe_id: int
    meal_type: str
    date: str
    created_at: str
    recipe_title: Optional[str] = None
    recipe_image: Optional[str] = None


# ---- 随机推荐查询 ----
class RandomQuery(BaseModel):
    """GET /api/recipes/random 的查询参数。"""
    category: Optional[str] = None
    meal_type: Optional[str] = None  # 按 meal_tags 包含性筛选（推荐）
    exclude_recent_days: int = 0


# ---- 图片搜索 ----
class SearchImageItem(BaseModel):
    url: str
    thumb: Optional[str] = None


# ---- 轮播 ----
class CarouselItem(BaseModel):
    id: int
    title: str
    image_url: Optional[str] = None
    category: Optional[str] = None


# ---- 日历 ----
class DayMealSlot(BaseModel):
    recipe_id: Optional[int] = None
    title: Optional[str] = None
    image_url: Optional[str] = None


class DayPlan(BaseModel):
    date: str
    weekday: str  # 周一~周日
    breakfast: DayMealSlot = DayMealSlot()
    lunch: DayMealSlot = DayMealSlot()
    dinner: DayMealSlot = DayMealSlot()


class WeekPlanResponse(BaseModel):
    days: List[DayPlan]


class MonthPlanResponse(BaseModel):
    year: int
    month: int
    days: List["MonthDayInfo"] = []


class MonthDayInfo(BaseModel):
    date: str
    has_records: bool        # 实际用餐记录（meals 表）
    has_plans: bool          # 预定记录（meal_plans 表）
    breakfast_planned: bool
    lunch_planned: bool
    dinner_planned: bool
    breakfast_ate: bool
    lunch_ate: bool
    dinner_ate: bool


class CalendarPlanCreate(BaseModel):
    """POST /api/calendar/plan 请求体。"""
    date: str = Field(..., description="YYYY-MM-DD")
    meal_type: str = Field(..., description="breakfast/lunch/dinner")
    recipe_id: int


class CalendarPlanDelete(BaseModel):
    """DELETE /api/calendar/plan 请求体。"""
    date: str = Field(..., description="YYYY-MM-DD")
    meal_type: str = Field(..., description="breakfast/lunch/dinner")


class ShoppingListItem(BaseModel):
    name: str
    amounts: List[str] = []   # 去重后的用量组合
    unit: Optional[str] = None


class ShoppingListResponse(BaseModel):
    items: List[ShoppingListItem] = []
