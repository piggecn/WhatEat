FROM python:3.12-slim AS builder
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --prefix=/install -r requirements.txt \
    -i https://pypi.tuna.tsinghua.edu.cn/simple --trusted-host pypi.tuna.tsinghua.edu.cn

FROM python:3.12-slim
ARG APP_VERSION=0.0.0
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    APP_VERSION=$APP_VERSION
WORKDIR /app
COPY --from=builder /install /usr/local
COPY . .
RUN mkdir -p /app/data/uploads
EXPOSE 8765
# 非 root 运行是后续安全优化项：当前 recipe_data 卷为 root 所有，切用户需配合卷迁移，先保持 root
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8765/', timeout=4).status < 400 else 1)"
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8765"]
