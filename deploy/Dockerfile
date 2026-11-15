# 隐迹 InvisMark · 零依赖运行镜像
# 只装 numpy（PNG 走内置编解码器），镜像体积小、断网可跑。
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    INVISMARK_HOST=0.0.0.0 \
    INVISMARK_PORT=8000 \
    INVISMARK_DB=/data/invismark.db \
    INVISMARK_DATA=/data

WORKDIR /app

# 可选：JPEG/WebP 支持
# RUN pip install --no-cache-dir pillow==10.*
RUN pip install --no-cache-dir "numpy>=1.24"

COPY pyproject.toml README.md LICENSE NOTICE ./
COPY invismark ./invismark
COPY docs ./docs

RUN pip install --no-cache-dir --no-deps -e .

VOLUME ["/data"]
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8000/healthz')"

CMD ["python", "-m", "invismark", "serve", "--host", "0.0.0.0", "--port", "8000"]
