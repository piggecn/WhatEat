# ---- Tailwind CSS 编译阶段（每次构建自动重编，模板改动无需手工编译） ----
FROM node:22-alpine AS css
WORKDIR /src/static/css
COPY static/css/input.css .
COPY app/templates /src/app/templates
COPY static/js /src/static/js
RUN npm install --no-save tailwindcss@4.3.3 @tailwindcss/cli@4.3.3 \
    && npx tailwindcss -i ./input.css -o ./tailwind.css \
    && rm -rf node_modules package.json package-lock.json

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
# OpenCV 运行库（OCR 用）：Debian 源换阿里云镜像，装完清理列表
RUN sed -i 's#deb.debian.org#mirrors.tuna.tsinghua.edu.cn#g' /etc/apt/sources.list.d/debian.sources 2>/dev/null || true;     sed -i 's#deb.debian.org#mirrors.tuna.tsinghua.edu.cn#g' /etc/apt/sources.list 2>/dev/null || true;     apt-get update -qq && apt-get install -y -qq --no-install-recommends libgl1 libglib2.0-0     && rm -rf /var/lib/apt/lists/*
COPY --from=builder /install /usr/local
COPY . .
COPY --from=css /src/static/css/tailwind.css /app/static/css/tailwind.css
RUN useradd -r -u 1000 whateat \
    && mkdir -p /app/data/uploads \
    && chown -R whateat:whateat /app
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
EXPOSE 8765
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8765/', timeout=4).status < 400 else 1)"
ENTRYPOINT ["docker-entrypoint.sh"]
