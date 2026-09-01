# 今天吃点啥 (WhatEat)

把家的味道，装进每个人的口袋里。

家庭食谱管理应用：菜谱记录、收藏、日历排餐、库存管理、随机推荐。数据完全私有，Docker 单容器部署，跑在自家 NAS 上。

## 主要功能

- 🍽 **菜谱管理**：记录标题、分类、餐次、食材、步骤，支持上传封面图
- ⭐ **收藏与搜索**：一键收藏，按分类/关键词筛选，搜索历史 + 结果高亮
- 🎲 **随机推荐**：不知道吃什么？随机抽一道，可排除最近吃过的
- 📅 **日历排餐**：按天安排早/午/晚三餐，每餐可配多道菜；月底回顾 + 按天购物清单
- 🥕 **库存（家里剩啥）**：看看手头食材能做什么
- 👨‍🍳 **烹饪模式**：步骤模式 + 语音朗读（TTS 多音色），做饭不碰手机
- 📷 **OCR 拍照导入**：拍纸质菜谱直接识别录入
- 🔄 **菜谱导入**：HowToCook 中文菜谱库 390 道 + TheMealDB + 网页链接导入（含豆果）+ 粘贴解析；离线菜谱索引 1281 道随镜像打包，断网也能查
- 🧮 **单位换算**：常用食材单位互转
- 🌱 **时令推荐**：当季食材推荐
- 🌗 **深浅色主题**
- 👨‍👩‍👧 **家人共享**：多账号，每个人独立收藏和记录
- 🔔 **版本更新**：自动检测新版本，管理员一键在线更新

## NAS 部署

```bash
# 1. 把本项目目录拷到 NAS 上，例如 /volume1/docker/whateat
cd /volume1/docker/whateat
# 2. 一键构建并启动
docker compose up -d --build
```

- 访问地址：`http://NAS的IP:8765`（手机同一局域网直接用浏览器打开）
- 默认管理员：`admin` / `admin123`（登录后到管理中心修改密码、添加家人账号）
- 数据存 Docker 卷 `whateat_recipe_data`，删除容器重建数据不丢

## 备份

```bash
docker run --rm -v whateat_recipe_data:/data -v $(pwd):/backup alpine tar czf /backup/backup.tar.gz -C /data .
```

恢复：把 `czf` 换成 `xzf` 反向执行。

## 升级

```bash
cd /volume1/docker/whateat
git pull
docker compose up -d --build
```

或直接用 Docker Hub 现成镜像：

```bash
docker run -d --name whateat \
  -p 8765:8765 \
  -v whateat_recipe_data:/app/data \
  --restart unless-stopped \
  piggecn/whateat:latest
```

## 常见问题

- **改访问端口**：改 `docker-compose.yml` 里 `ports` 的 `8765:8765` 左侧数字
- **局域网访问**：确认 NAS 防火墙放行端口，手机访问 `http://NAS的IP:8765`
- **忘记管理员密码**：删数据卷 `whateat_recipe_data` 重建（会清空全部数据）

## 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件
