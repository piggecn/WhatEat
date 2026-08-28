# 今天吃点啥 (WhatEat)

把家的味道，装进每个人的口袋里。

一款面向家庭的食谱管理应用，支持菜谱记录、收藏、周计划安排和随机推荐，数据完全私有，不依赖任何第三方云服务。

## 功能特点

- 🍽 **记录菜谱**：标题、分类、餐次、食材、步骤，支持上传封面图
- ⭐ **收藏管理**：一键收藏，按分类/关键词快速筛选
- 🎲 **随机推荐**：不知道吃什么？随机抽一道菜，可排除最近吃过的
- 📅 **周计划**：提前安排好每天的三餐，月底回顾饮食记录
- 👨‍👩‍👧 **家人共享**：多账号管理，每个人独立收藏和记录
- 🔔 **版本更新**：自动检测新版本，管理员一键在线更新

## 快速开始

### 1. 克隆项目

```bash
git clone https://github.com/piggecn/WhatEat.git
cd WhatEat
```

### 2. 启动服务

```bash
docker compose up -d
```

首次启动会自动初始化数据库，约 1-2 分钟。

### 3. 访问应用

打开浏览器访问：`http://localhost:8765`

默认管理员账号：
- 用户名：`admin`
- 密码：`admin123`

建议在「管理中心」修改密码并添加家庭成员账号。

## docker-compose.yml 说明

```yaml
services:
  whateat:
    build: .                    # 从当前目录构建镜像
    image: whateat:latest       # 本地镜像名称
    container_name: whateat     # 容器名称
    ports:
      - "127.0.0.1:8765:8765"   # 映射端口（仅本机可访问）
    volumes:
      - recipe_data:/app/data   # 数据持久化卷
    restart: unless-stopped     # 异常时自动重启

volumes:
  recipe_data:                  # 命名卷，存储数据库和上传文件
```

### 关键配置说明

| 配置项 | 说明 | 建议值 |
|--------|------|--------|
| `ports` | 访问端口 | `8765` 或改为你需要的端口 |
| `volumes` | 数据持久化 | 必须保留，否则数据会丢失 |
| `restart` | 重启策略 | `unless-stopped` 推荐 |

### 数据持久化

所有数据（食谱、用户、图片）存储在 Docker 卷 `recipe_data` 中。即使删除容器重新创建，数据也不会丢失。

备份方法：
```bash
docker run --rm -v whateat_recipe_data:/data -v $(pwd):/backup alpine tar czf /backup/backup.tar.gz -C /data .
```

恢复方法：
```bash
docker run --rm -v whateat_recipe_data:/data -v $(pwd):/backup alpine tar xzf /backup/backup.tar.gz -C /data
```

## 版本更新

应用内置版本检测功能：
1. 进入「关于」页面
2. 点击「服务器版本」按钮检测更新
3. 发现新版本时，管理员可点击「在线更新」一键拉取最新镜像并重启服务

发布流程：
```bash
git tag v0.0.2
git push origin v0.0.2
```

推送 Tag 后，GitHub Actions 自动构建镜像并推送到 Docker Hub。

## 安全说明

- 默认仅允许本机访问（`127.0.0.1:8765`）
- 如需外网访问，建议使用 Nginx 反代 + HTTPS
- 数据库密钥自动生成，重启后不变
- 密码使用 bcrypt 加密存储

## 常见问题

**Q: 如何修改访问端口？**
```yaml
ports:
  - "8080:8765"  # 将 8765 改为其他端口
```

**Q: 如何暴露到局域网？**
```yaml
ports:
  - "0.0.0.0:8765:8765"  # 允许局域网访问
```

**Q: 如何迁移数据？**
直接复制 `recipe_data` 卷或使用备份命令导出。

**Q: 忘记管理员密码？**
重置数据库：
```bash
docker volume rm whateat_recipe_data
docker compose up -d
```
注意：这会清除所有数据！

## 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件
