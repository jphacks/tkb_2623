FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# CLIPの重みをビルド時に取得し、ローカルキャッシュに焼き込む。
ENV CLIP_DEVICE=cpu
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('sentence-transformers/clip-ViT-B-32')"

# HF_HUB_OFFLINE未設定だと、キャッシュがあっても毎リクエストHugging Face Hubへ
# メタデータ確認の通信をしてしまい、外部ネットワーク状況次第でレイテンシが不安定になっていた
# (ログに"unauthenticated requests to the HF Hub"警告が出ていた)。完全オフライン固定で解消する。
ENV HF_HUB_OFFLINE=1
ENV TRANSFORMERS_OFFLINE=1

COPY . .

ENV PORT=8080
CMD exec uvicorn api:app --host 0.0.0.0 --port ${PORT} --workers 1
