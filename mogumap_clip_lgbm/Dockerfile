FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# CLIPの重みをビルド時に取得し、Cloud Runのコールドスタート時にHugging Faceへ
# アクセスしないようにする(min-instances=0運用でも初回応答が遅くなりすぎないため)。
ENV CLIP_DEVICE=cpu
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('sentence-transformers/clip-ViT-B-32')"

COPY . .

ENV PORT=8080
CMD exec uvicorn api:app --host 0.0.0.0 --port ${PORT} --workers 1
