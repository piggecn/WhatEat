#!/bin/sh
set -e
# 旧版本数据卷可能由 root 创建：以 root 启动时先修正归属，再降权运行（安全 + 平滑迁移）
mkdir -p /app/data/uploads
chown -R whateat:whateat /app/data 2>/dev/null || true
if command -v setpriv >/dev/null 2>&1; then
    exec setpriv --reuid=whateat --regid=whateat --clear-groups -- \
        uvicorn app.main:app --host 0.0.0.0 --port 8765
else
    exec uvicorn app.main:app --host 0.0.0.0 --port 8765
fi
