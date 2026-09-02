# 今天吃点啥 · Flutter App 任务清单

> 目标：把 Docker 后端（FastAPI）的全部能力 + Web 端的全部 UI 设计，逐一对齐到 Flutter App。
> 定位：**APK 是纯客户端**。所有数据、业务逻辑都在 Docker 服务端；APK 只负责登录 + 调 API + 展示与交互。
> 状态约定：`- [ ]` 未开始 · `- [x]` 已完成。当前全部已完成。

## 架构定位（本次对齐的关键决策）

1. **纯客户端**：管理员管理中心、系统设置、数据备份/导入导出、运行日志、服务端在线更新 → **全部只留在 Docker/Web 端，不进 APK**。
2. **服务器地址不硬编码**：APK 登录页需填写「服务器 IP（域名）+ 端口 + 账号 + 密码」才能登录；也可扫服务端「关于页 → 手机客户端配置」生成的二维码自动填地址。地址存在本地 `shared_preferences`，所有 API 调用动态拼 base URL。这样 APK 内容与服务端内容天然同步，且无需把服务器地址写死在包里。
3. **数据备份只在服务端**：数据存服务端 SQLite + `data/uploads`，由 `GET /api/data/export` 备份；客户端无本地数据，无需备份能力。
4. **版本更新跟服务端一致**：APK 启动时调 `GET /api/app/check`（免登录），比对 GitHub Releases 最新版，有新版则提示下载 APK。
5. **个人中心 / 收藏 / 日历 / 首页**：与服务端功能一致，纯 API 调用实现。
6. **Logo 与 Docker 一致**：复用 `static/logo.png`（启动器图标 + 登录页/AppBar 内 logo）。
7. **相机 / 相册**：发布/编辑菜谱时拍照或从相册选图，走 `POST /api/upload` 上传（jpg/png/webp ≤ 5MB）。
8. **接收小红书 / 公众号分享**：其他 App 分享到「今天吃点啥」的文本（小红书笔记、公众号食谱），经系统分享面板进入 APK，拿到文本后调 `POST /api/recipe-api/parse-paste` 解析出标题/食材/步骤，再走发布流程生成自己的菜谱（图片走相机/相册）。

## 对齐对象

### 后端 API（14 个模块）——APK 接入范围

| 模块 | 端点 | APK |
|------|------|-----|
| 认证 | `POST /api/auth/login` | ✅ 登录 |
| 认证 | `GET /api/auth/me` | ✅ 启动校验 token / 自动登录 |
| 应用 | `GET /api/app/check` | ✅ 版本更新（GitHub Releases） |
| 应用 | `GET/DELETE /api/app/logs` | ❌ 仅服务端（管理员） |
| 菜谱 | `GET /api/recipes`（列表） | ✅ |
| 菜谱 | `GET /api/recipes/favorites` | ✅ 收藏页 |
| 菜谱 | `GET /api/recipes/{id}` | ✅ 详情 |
| 菜谱 | `POST /api/recipes` | ✅ 发布 |
| 菜谱 | `PUT /api/recipes/{id}` | ✅ 编辑 |
| 菜谱 | `DELETE /api/recipes/{id}` | ✅ 删除 |
| 菜谱 | `POST /api/recipes/{id}/favorite` | ✅ 收藏/取消 |
| 随机 | `GET /api/recipes/random` | ✅ 今天吃点啥 |
| 轮播 | `GET /api/recipes/carousel` | ✅ 首页轮播 |
| 打卡 | `POST/GET /api/meals`、`GET /recent`、`DELETE /{id}` | ✅ 用餐打卡 |
| 日历 | `GET /week`、`POST/DELETE /plan`、`GET /month`、`GET /shopping-list` | ✅ 日历 + 购物清单 |
| 用户 | `GET/PUT /api/users/profile` | ✅ 个人中心 |
| 用户 | `GET /api/users/get_me`、`PUT /update_me`、`PUT /me/password`、`POST /avatar/upload` | ✅ 个人中心 |
| 用户 | `GET /api/users/list`、`POST ""`、`DELETE /{id}` | ❌ 仅服务端（管理员） |
| 上传 | `POST /api/upload` | ✅ 发布/编辑传图 |
| 系统 | `GET /api/system/settings` | ✅ 登录页/关于页取服务器地址 |
| 系统 | `GET/PUT /api/system/settings/admin`、`POST /update`、`POST /proxy/test` | ❌ 仅服务端（管理员） |
| 数据 | `GET /api/data/export`、`POST /api/data/import` | ❌ 仅服务端（数据备份） |
| 在线食谱 | `GET /search`、`GET /translate-keyword`、`POST /prepare`、`POST /parse-paste` | ✅ 在线导入 |
| 图片搜索 | `GET /api/search-image` | ✅ 配图 |

### Web 端设计系统（`static/css/style.css`）

| Token | 浅色值 | 用途 |
|-------|--------|------|
| `--fr-primary` | `#FF6B35` | 品牌主色（食欲橙） |
| `--fr-primary-hover` | `#E85A28` | 主色悬停 |
| `--fr-primary-soft` | `#FFF0E9` | 主色浅底 |
| `--fr-background` | `#FFF8F0` | 暖米色背景 |
| `--fr-foreground` | `#3D3530` | 主文字（暖棕） |
| `--fr-card` | `#FFFFFF` | 卡片底 |
| `--fr-muted` | `#F5EDE4` | 次级底 |
| `--fr-muted-foreground` | `#8A8078` | 次要文字 |
| `--fr-border` / `--fr-input` | `#EFE5DA` | 边框 / 输入框 |
| `--fr-ring` | `#FF6B35` | 聚焦环 |
| `--fr-state-success` | `#2D936C` | 成功 / 占位渐变 |
| `--fr-state-warning` | `#F5A623` | 警告 |
| `--fr-state-error` | `#E5484D` | 错误 / 收藏红 |
| 圆角 | 8 / 12 / 16 / full | small/medium/large/full |
| 字体 | Noto Sans SC | 中文字体 |
| 深色 | `#1A1612` 底 / `#2A2520` 卡 等 | 已含 dark token |
| 图标 | Lucide（线性） | Web 端图标库 |

### 关键交互范式（来自 `app/templates/`）

- 首页：轮播 + 「今天吃点啥？」随机大按钮 + 今日已选条 + 搜索/分类/排序 + 卡片网格
- 菜谱卡片：图 + 心形收藏 + 标题 + 分类 tag + 作者头像 + 烹饪时间
- 无图占位：`primary→success` 渐变 + 厨师帽图标
- 通用：毛玻璃、圆角卡片、`fr-btn`(primary/secondary/ghost)、`fr-tag`、确认弹窗、Toast、加载/空/错误三态
- 登录页：右上角 ⚙ 扫描二维码配置（扫码自动填服务器地址）
- 关于页（Web）：手机客户端配置 + 二维码 + 版本更新（这些只留在服务端）

### 关键约定（本次新增）

- 二维码内容：`{"base_url": "http://<ip|域名>:<端口>"}`（由服务端关于页生成，APK 扫码解析）
- 版本更新：`GET /api/app/check` 返回 `{version, notes, pre_release, assets:[{name,url}]}`，APK 比对本地版本后从 `assets` 取 APK 下载链接
- 分享接收：APK 注册 `ACTION_SEND`（`text/plain`）intent-filter，接收小红书/公众号分享的文本 → 调 `POST /api/recipe-api/parse-paste` 解析（该端点已支持中文笔记，如小红书）
- 相机/相册：走 `POST /api/upload`（jpg/png/webp ≤ 5MB），返回 `{path}`；图片权限为相机 + 相册（`READ_MEDIA_IMAGES`）

## 任务清单

### 阶段 0（P0）基础设施 + 设计系统 —— 一切地基

- [x] **T0.1** 服务器地址配置：新增 `ServerConfig`（baseUrl 读写 `shared_preferences`），移除 [config.dart](file:///d:/git/源码/WhatEat/mobile/lib/config.dart) 里的硬编码地址，`ApiClient` 改为动态读取 baseUrl
- [x] **T0.2** 主题令牌：把 `--fr-*` 浅色 token 映射为 Flutter `ColorScheme` / `ThemeData`
- [x] **T0.3** 深色主题：用 dark token 建 `darkTheme`
- [x] **T0.4** 字号层级（h1/h2/h3/body/caption/tag）+ 圆角常量 + Noto Sans SC 字体（需新增字体资源）
- [x] **T0.5** 通用组件：`FrButton` / `FrCard` / `FrTag` / `EmptyState` / `LoadingState` / 占位渐变（渐变 + 厨师帽图标）
- [x] **T0.6** 统一 HTTP 客户端：升级 [api_client.dart](file:///d:/git/源码/WhatEat/mobile/lib/services/api_client.dart)（动态 baseUrl + 统一错误/超时/鉴权头 + 401 自动登出）
- [x] **T0.7** Logo 资源：复制 `static/logo.png` 到 Flutter `assets/` 并在 pubspec 注册
- [x] **T0.8** Android 原生配置：[AndroidManifest.xml](file:///d:/git/源码/WhatEat/mobile/android/app/src/main/AndroidManifest.xml) 增加相机/相册权限（`CAMERA`、`READ_MEDIA_IMAGES`）+ 分享接收 intent-filter（`android.intent.action.SEND`，`text/plain`）

### 阶段 1（P0）导航骨架 + 登录 + 账户

- [x] **T1.1** 底部导航（首页/收藏/日历/我的）+ 统一 AppBar（logo + 标题 + 头像）
- [x] **T1.2** 登录页重构：logo + 服务器地址（IP/域名 + 端口）输入 + 「扫描二维码」按钮 + 账号密码 + 记住登录
  - API：`POST /api/auth/login`、`GET /api/system/settings`（校验地址连通）
  - 扫码：新增 `mobile_scanner` 依赖，解析 `{"base_url": "..."}`
  - 服务器地址持久化到 `shared_preferences`
- [x] **T1.3** 个人中心：头像/昵称/改密码/轮播偏好
  - API：`GET/PUT /api/users/profile`、`PUT /api/users/me/password`、`POST /api/users/avatar/upload`

### 阶段 2（P0）菜谱「读」闭环

- [x] **T2.1** 菜谱卡片组件（图 + 心形 + 标题 + 分类 tag + 作者头像 + 时间）
- [x] **T2.2** 首页：轮播 + 搜索/分类/排序 + 卡片网格 + 加载/空态
  - API：`GET /api/recipes`、`GET /api/recipes/carousel`
- [x] **T2.3** 详情页：大图头 + 食材清单 + 步骤 + 作者 + 收藏
  - API：`GET /api/recipes/{id}`
- [x] **T2.4** 收藏：心形切换 + 收藏页
  - API：`POST /api/recipes/{id}/favorite`、`GET /api/recipes/favorites`

### 阶段 3（P0）菜谱「写」闭环

- [x] **T3.1** 发布/编辑：表单（标题/分类/餐次/份量/时间）+ 图片上传（拍照 / 从相册选，`image_picker`）+ 食材/步骤列表编辑
  - API：`POST/PUT /api/recipes`、`POST /api/upload`
  - 权限：相机 + 相册（见 T0.8）
- [x] **T3.2** 删除菜谱 + 确认弹窗
  - API：`DELETE /api/recipes/{id}`

### 阶段 4（P1）随机推荐 + 用餐打卡（产品灵魂）

- [x] **T4.1** 「今天吃点啥？」随机推荐：大按钮 + 弹窗（分类/餐次/排除近期 + 换一个 + 就它了）
  - API：`GET /api/recipes/random`
- [x] **T4.2** 用餐打卡：今日已选条 + 记录/删除
  - API：`GET/POST/DELETE /api/meals`

### 阶段 5（P1）日历 + 购物清单

- [x] **T5.1** 日历页：周/月视图 + 排餐计划
  - API：`GET /api/calendar/week`、`GET /api/calendar/month`、`POST/DELETE /api/calendar/plan`
- [x] **T5.2** 购物清单：按排餐聚合食材
  - API：`GET /api/calendar/shopping-list`

### 阶段 6（P2）在线食谱 + 图片搜索（解决空库）

- [x] **T6.1** 在线食谱搜索/导入 + 粘贴解析 + 接收分享导入
  - API：`GET /api/recipe-api/search`、`POST /api/recipe-api/prepare`、`POST /api/recipe-api/parse-paste`
  - 分享接收：`receive_sharing_intent` 监听 `ACTION_SEND` 文本 → 自动填入 `parse-paste` → 预览解析结果 → 走 T3.1 发布
  - 入口：小红书/公众号 App 内「分享 → 更多 → 今天吃点啥」
- [x] **T6.2** 图片搜索（给菜谱配图）
  - API：`GET /api/search-image`

### 阶段 7（P1，发布期关键）发布打磨

- [x] **T7.1** 关于页：logo + 版本号 + 当前服务器地址（不含手机客户端配置，那是服务端功能）
- [x] **T7.2** 版本更新：启动调 `GET /api/app/check`，比对本地版本（需新增 `package_info_plus`），有新版提示下载安装 GitHub Release 里的 APK
- [x] **T7.3** App 启动器图标使用 Docker 的 `logo.png`

## 增量对齐（2026-08-28 Web/Mobile 对比修复）

针对「端对齐对比清单」的 5 项差异，本轮已在移动端落地：

- [x] **T8.1** 收藏列表响应解析加固：`api_client.fetchFavorites` 用 `_int()` 容错解析 `total`，兼容后端 `{total, page, page_size, items}` 且支持 `has_more` 字段
- [x] **T8.2** 首页轮播图可点击：整块透明 `GestureDetector` 覆盖卡片 + 右上角箭头提示，点击跳 `/recipes/{id}`；多张时增加圆点/长条页码指示（`PageController` 跟踪当前页）
- [x] **T8.3** 关于页版本检测：「版本」行可点击触发检测（`checkApp(force: true)` 绕过服务端缓存），展示 检测中/已是最新版本/发现新版本（含 notes + 「去更新」跳 APK 下载）/检测失败可重试
- [x] **T8.4** 「今天吃点啥」对齐 Web：banner 卡片改为居中主色大按钮；点击打开**居中大弹窗**（`Dialog`，手机 88% 屏高、平板限 720）；弹窗内含分类/餐次下拉 + 「排除最近 3 天吃过」勾选 + 换一个 + 「就它了」（打卡 `POST /api/meals` 后回到今日已选条），并展示服务端「已自动放宽条件」提示
- [x] **T8.5** 搜索 API 可用性核实：后端 `GET /api/recipe-api/search`、`POST /api/recipe-api/prepare` 均已实现且与移动端 `searchOnlineRecipe` / `prepareOnlineRecipe` 调用一致，无需改动

## 明确不做（仅服务端 / Docker）

- 管理员管理中心（用户管理 / 系统设置）
- 数据备份 / 导入导出（`/api/data/*`）
- 运行日志（`/api/app/logs`）
- 服务端在线更新（`/api/system/update`）

## 新增依赖（阶段推进时安装）

| 依赖 | 用途 | 触发任务 |
|------|------|----------|
| `mobile_scanner` | 登录页扫码填服务器地址 | T1.2 |
| `package_info_plus` | 取本地版本号做版本比对 | T7.2 |
| `image_picker` | 拍照 / 相册选图（菜谱图） | T3.1 |
| `receive_sharing_intent` | 接收小红书/公众号分享文本 | T6.1 |
| Noto Sans SC 字体资源 | 中文字体 | T0.4 |

## 依赖关系

```
阶段 0（地基：服务器地址 + 设计系统 + HTTP 客户端）
   └─> 阶段 1（导航 + 登录 + 账户）
         └─> 阶段 2 / 3（读 / 写闭环，可并行）
               └─> 阶段 4 / 5（产品差异）
                     └─> 阶段 6（空库补齐）
阶段 7（发布打磨）在阶段 1 完成后任意时间可做
```

## 环境速查（避免重复踩坑）

- 项目：`D:\git\WhatEat\mobile`（包 `cn.piggecn.whateat`）。**2026-09-03 从 `D:\git\源码\WhatEat\mobile` 迁来**：路径含中文 `源码` 时 `flutter analyze` 的 LSP 通道 JSON 消息被多字节路径截断崩溃（exit 255 FormatException），ASCII 路径下正常；mobile 目录今后只存在于 git 副本，**源码→git 副本做 robocopy /MIR 同步时必须 /XD mobile**，否则会删掉 Flutter 工程
- 后端：Docker 容器 `whateat` @ `127.0.0.1:8765`（模拟器内用 `10.0.2.2:8765`）
- 测试账号：`admin / admin123`
- 模拟器：AVD `whateat_avd`（android-36 google_apis x86_64），`flutter run -d emulator-5554`
- 构建/运行需先设 `$env:JAVA_HOME = 'D:\app\android\jbr'`
- 服务器地址改为登录页动态配置后，`10.0.2.2` 仅作为「真机/模拟器访问宿主机」的填写示例，不再写死

## 对齐 Web v0.0.4 差距清单（2026-09-03 审计）

网页端演进后 Flutter 未跟上，且**日历数据模型已与服务端不兼容**（服务端 week/month 每餐改返回数组，客户端按单对象解析→空）。按依赖与价值排序：

### P0 数据正确性 + 日历

- [x] **T9.1** 日历模型对齐多菜数组：`models/calendar.dart` 的 `CalendarDay.breakfast/lunch/dinner` 改 `List<MealSlot>`（兼容旧 Map 格式），`MonthDayInfo` 补每餐菜品数组；`deletePlan` 支持 `recipe_id` 单删一道
- [x] **T9.2** 周视图多菜 UI：每格多道菜卡片 + 「再加一道」+ 单删；日详情 sheet 同步多菜
- [x] **T9.3** 购物清单对齐：解析 items 里的 `total`、新增 `by_day` 按天分组模式（汇总/按天双 Tab + 勾选）
- [x] **T9.4** 随机填充本周（对空槽循环 random+plan）

### P0 库存 + 忌口

- [x] **T9.5** 库存页（家里剩啥）：GET/POST/DELETE `/api/inventory`，入口放「我的」；随机推荐加「仅用现有食材」勾选（random 传 `only_in_stock`）
- [x] **T9.6** 忌口：Recipe 模型补 `diet_tags`（编辑页预设+自定义、详情展示🚫）；Profile 补 `avoid_tags`（我的忌口编辑，随机推荐服务端联动排除）

### P1 烹饪模式 + TTS

- [x] **T9.7** 烹饪模式：详情页入口 → 全屏步骤大字（逐屏翻页）+ mm:ss 计时器 + 上一步/下一步
- [x] **T9.8** TTS 朗读：接服务端 `GET /api/tts/voices` + `POST /api/tts`（edge-tts 5 音色 mp3，rate/pitch），新增音频播放依赖；设置面板（音色/语速/音调/自动朗读）。WebView 方案的 speechSynthesis 问题不存在于此（原生播放 mp3）

### P1 详情/编辑对齐

- [ ] **T9.9** 食材勾选划线 + 常用单位换算切换（复刻服务端 convert_amount：克→两、毫升→汤匙、斤→公斤）
- [ ] **T9.10** 复制菜谱文本 + 系统分享（share_plus）

### P1 导入补齐

- [ ] **T9.11** 链接导入：`POST /api/recipe-api/fetch-url`（豆果等），并入发布入口
- [ ] **T9.12** 粘贴导入加拍照 OCR（`POST /api/ocr`，image_picker 已有）
- [ ] **T9.13** 在线菜谱 source 切换（TheMealDB/中文菜谱库）+ 中英关键词切换 + **prepare/search 补传 source（修 howtocook 结果被误英转中的 bug）**
- [ ] **T9.14** 图片搜索渠道切换（pixabay/pixabay_zh/wikimedia）+ 手动输 URL

### P2 首页/收藏体验

- [ ] **T9.15** 搜索关键词高亮（TextSpan）+ 搜索历史（SharedPreferences 8 条）
- [ ] **T9.16** 列表排序（created_desc/cook_time/alpha）+ 收藏页筛选
- [ ] **T9.17** 轮播自动播放（4s，交互暂停）+ 时令提示条（按月份四季文案）
- [ ] **T9.18** 个人中心：头像上传+预设 emoji、轮播设置补 favorites 项+滑条

### P2 收尾

- [ ] **T9.19** 删除死代码 `recipe_list_screen.dart`
- [ ] **T9.20** 模拟器 E2E 冒烟 + 构建正式 APK

依赖：T9.1 → T9.2/T9.3/T9.4；T9.5/T9.6 同批（随机联动）；T9.8 依赖 T9.7；其余独立。
