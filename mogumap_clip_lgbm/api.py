"""MoguMap AIバックエンドAPI。Supabase Edge Function経由でのみ呼ぶ想定(共有シークレット認証)。"""
from __future__ import annotations

import os
from threading import Lock
from typing import Any

from fastapi import FastAPI, HTTPException, Header, Depends
from pydantic import BaseModel, Field

from ml import train_user, predict_for_user, has_model, MIN_RECORDS
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
    """未学習なら先に学習してから推論する(on-demand)。"""
    if len(body.history) < MIN_RECORDS:
        raise HTTPException(400, f"need >={MIN_RECORDS} registered stores before recommendations")
    if not has_model(body.user_id):
        try:
            train_user(body.user_id, body.history)
        except ValueError as e:
            raise HTTPException(400, str(e))
    conditions = extract_conditions(body.free_text)
    candidates = search_candidates(conditions, body.lat, body.lng)
    if not candidates:
        return {"predictions": [], "conditions": conditions}
    try:
        predictions = predict_for_user(body.user_id, body.history, candidates)
    except FileNotFoundError as e:
        raise HTTPException(409, str(e))
    return {"predictions": predictions[:3], "conditions": conditions}
