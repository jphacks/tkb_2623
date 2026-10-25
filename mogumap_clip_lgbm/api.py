"""MoguMap AIバックエンドAPI。Supabase Edge Function経由でのみ呼ぶ想定(共有シークレット認証)。"""
from __future__ import annotations

import os
import time
from threading import Lock
from typing import Any

from fastapi import FastAPI, HTTPException, Header, Depends
from pydantic import BaseModel, Field

from ml import train_user, predict_for_user, MIN_RECORDS
from recommend import extract_conditions, search_candidates

app = FastAPI(title="MoguMap AI Backend", version="0.2")
_train_locks: dict[str, Lock] = {}


def auth(x_api_key: str | None = Header(default=None)) -> None:
    key = os.getenv("AI_BACKEND_API_KEY")
    if not key or x_api_key != key:
        raise HTTPException(401, "Invalid API key")


class TrainRequest(BaseModel):
    user_id: str
    records: list[dict[str, Any]] = Field(min_length=MIN_RECORDS, max_length=2000)


class PredictRequest(BaseModel):
    user_id: str
    history: list[dict[str, Any]] = Field(default_factory=list, max_length=2000)
    candidates: list[dict[str, Any]] = Field(min_length=1, max_length=100)


class RecommendRequest(BaseModel):
    user_id: str
    free_text: str = Field(min_length=1, max_length=500)
    lat: float
    lng: float
    history: list[dict[str, Any]] = Field(default_factory=list, max_length=2000)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/train", dependencies=[Depends(auth)])
def train_endpoint(body: TrainRequest):
    lock = _train_locks.setdefault(body.user_id, Lock())
    if not lock.acquire(blocking=False):
        raise HTTPException(409, "training already running for this user")
    try:
        return train_user(body.user_id, body.records)
    except ValueError as e:
        raise HTTPException(400, str(e))
    finally:
        lock.release()


@app.post("/predict", dependencies=[Depends(auth)])
def predict_endpoint(body: PredictRequest):
    try:
        return {"predictions": predict_for_user(body.user_id, body.history, body.candidates)}
    except FileNotFoundError as e:
        raise HTTPException(409, str(e))
    except ValueError as e:
        raise HTTPException(400, str(e))


@app.post("/recommend", dependencies=[Depends(auth)])
def recommend_endpoint(body: RecommendRequest):
    """渡された最新の履歴で毎回学習し直してから推論する(on-demand)。

    5件ごとの自動バッチ学習は見送ったため、ここで常に最新のhistoryで学習し直すことで
    モデルを更新し続ける(小データなのでLightGBMの再学習コストは小さい)。
    """
    if len(body.history) < MIN_RECORDS:
        raise HTTPException(400, f"need >={MIN_RECORDS} registered stores before recommendations")

    # 原因不明の遅延(同じ件数でも呼ぶたびに遅くなる)を調査するための一時的な計測ログ。
    t0 = time.monotonic()
    try:
        model_stats = train_user(body.user_id, body.history)
    except ValueError as e:
        raise HTTPException(400, str(e))
    t1 = time.monotonic()
    conditions = extract_conditions(body.free_text)
    t2 = time.monotonic()
    candidates = search_candidates(conditions, body.lat, body.lng)
    t3 = time.monotonic()
    print(
        f"[timing] user={body.user_id} history={len(body.history)} "
        f"train={t1 - t0:.1f}s gemini={t2 - t1:.1f}s places={t3 - t2:.1f}s",
        flush=True,
    )
    if not candidates:
        return {"predictions": [], "conditions": conditions, "model_stats": model_stats}
    try:
        predictions = predict_for_user(body.user_id, body.history, candidates)
    except FileNotFoundError as e:
        raise HTTPException(409, str(e))
    t4 = time.monotonic()
    print(f"[timing] user={body.user_id} predict={t4 - t3:.1f}s total={t4 - t0:.1f}s", flush=True)
    return {"predictions": predictions[:3], "conditions": conditions, "model_stats": model_stats}
