"""MoguMap AIバックエンドAPI。Supabase Edge Function経由でのみ呼ぶ想定(共有シークレット認証)。"""
from __future__ import annotations

import os
import logging
import secrets
import time
from collections import deque
from threading import Lock
from typing import Any

from fastapi import FastAPI, HTTPException, Header, Depends
from pydantic import BaseModel, Field

from policy import MIN_TRAIN_RECORDS, MIN_ML_RECOMMEND_RECORDS, model_available
from history import valid_history
from repository import Repository
from recommend import extract_conditions, search_candidates, with_candidate_photos, gemini_recommend

log = logging.getLogger(__name__)


def train_user(*args, **kwargs):
    from ml import train_user as train
    return train(*args, **kwargs)


def predict_for_user(*args, **kwargs):
    from ml import predict_for_user as predict
    return predict(*args, **kwargs)

app = FastAPI(title="MoguMap AI Backend", version="0.3")
_train_locks: dict[str, Lock] = {}


def auth(x_api_key: str | None = Header(default=None)) -> None:
    key = os.getenv("AI_BACKEND_API_KEY")
    if not key or not secrets.compare_digest(x_api_key or "", key):
        raise HTTPException(401, "Invalid API key")


# 共有シークレットが万一漏れた場合の被害を抑えるための簡易レート制限。
# インスタンス単位のメモリ内カウントなので(Cloud Runは複数インスタンスに分散しうる)
# 厳密なグローバル制限ではないが、Gemini/Places/学習を呼ぶ高コストエンドポイントの
# 上限を低く抑える保険として十分。
RATE_LIMIT_PER_MINUTE = int(os.getenv("RATE_LIMIT_PER_MINUTE", "20"))
_request_times: deque[float] = deque()
_rate_lock = Lock()


def rate_limit() -> None:
    now = time.monotonic()
    with _rate_lock:
        while _request_times and now - _request_times[0] > 60:
            _request_times.popleft()
        if len(_request_times) >= RATE_LIMIT_PER_MINUTE:
            raise HTTPException(429, "rate limit exceeded, try again shortly")
        _request_times.append(now)


class TrainRequest(BaseModel):
    user_id: str = Field(pattern=r"^[A-Za-z0-9_-]{1,128}$")
    records: list[dict[str, Any]] = Field(min_length=MIN_TRAIN_RECORDS, max_length=2000)


class PredictRequest(BaseModel):
    user_id: str = Field(pattern=r"^[A-Za-z0-9_-]{1,128}$")
    history: list[dict[str, Any]] = Field(default_factory=list, max_length=2000)
    model_version: str = Field(pattern=r"^[A-Za-z0-9_-]{1,128}$")
    candidates: list[dict[str, Any]] = Field(min_length=1, max_length=100)


class RecommendRequest(BaseModel):
    user_id: str = Field(pattern=r"^[A-Za-z0-9_-]{1,128}$")
    free_text: str = Field(min_length=1, max_length=500)
    lat: float = Field(ge=-90, le=90, allow_inf_nan=False)
    lng: float = Field(ge=-180, le=180, allow_inf_nan=False)
    history: list[dict[str, Any]] = Field(default_factory=list, max_length=2000)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/train", dependencies=[Depends(auth), Depends(rate_limit)])
def train_endpoint(body: TrainRequest):
    lock = _train_locks.setdefault(body.user_id, Lock())
    if not lock.acquire(blocking=False):
        raise HTTPException(409, "training already running for this user")
    try:
        # Developer-only training: never publish to ai_model_status.
        history = valid_history(body.records, body.user_id)
        return train_user(body.user_id, history)
    except ValueError as e:
        raise HTTPException(400, str(e))
    finally:
        lock.release()


@app.post("/predict", dependencies=[Depends(auth), Depends(rate_limit)])
def predict_endpoint(body: PredictRequest):
    try:
        return {"predictions": predict_for_user(body.user_id, body.history, body.candidates, version=body.model_version)}
    except FileNotFoundError as e:
        raise HTTPException(409, str(e))
    except ValueError as e:
        raise HTTPException(400, str(e))


@app.post("/recommend", dependencies=[Depends(auth), Depends(rate_limit)])
def recommend_endpoint(body: RecommendRequest):
    """Inference only. Training is handled exclusively by the worker/CLI."""
    try:
        history = valid_history(body.history, body.user_id)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    started = time.monotonic()
    status = None
    repository = None
    if len(history) >= MIN_ML_RECOMMEND_RECORDS:
        try:
            repository = Repository()
            status = repository.status(body.user_id)
        except Exception as exc:
            # Safe fallback; never log tokens, payloads, or upstream error bodies.
            log.warning("model_status_unavailable error=%s", type(exc).__name__)
    try:
        conditions = extract_conditions(body.free_text)
        candidates = search_candidates(conditions, body.lat, body.lng)
        mode = "gemini"
        predictions = None
        if model_available(status):
            try:
                # Check generation before downloading candidate photos. Missing/corrupt
                # artifacts trigger repair even when Places returns no candidates.
                from ml import has_model
                if not has_model(body.user_id, status["model_version"]):
                    raise FileNotFoundError("published model unavailable")
                photos = with_candidate_photos(candidates)
                predictions = predict_for_user(body.user_id, history, photos,
                                               version=status["model_version"])[:3]
                mode = "lightgbm"
            except Exception as exc:
                log.warning("model_fallback error=%s", type(exc).__name__)
                if repository is not None:
                    try:
                        repository.repair(body.user_id)
                    except Exception as repair_exc:
                        log.warning("model_repair_unavailable error=%s", type(repair_exc).__name__)
        if predictions is None:
            predictions = gemini_recommend(body.free_text, history, candidates)
        log.info("recommend mode=%s history=%d candidates=%d total=%.3f",
                 mode, len(history), len(candidates), time.monotonic() - started)
        return {"predictions": predictions, "conditions": conditions, "mode": mode}
    except Exception as exc:
        log.warning("recommend_unavailable error=%s", type(exc).__name__)
        raise HTTPException(502, "現在おすすめを取得できません。しばらくしてから再度お試しください") from exc
