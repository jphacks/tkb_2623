"""MoguMap AIバックエンド: 凍結CLIP特徴量 + ユーザーごとのLightGBM回帰。

1ユーザー1モデル(Notion仕様通り)。CLIPは全ユーザー共有・凍結の特徴抽出器。
1人あたりのデータが5〜数十件と少ないため、LightGBMのハイパーパラメータはデータ量に応じて
動的に絞り、評価は5-FoldではなくLOOCV(leave-one-out)を使う。
"""
from __future__ import annotations

import base64
import io
import os
from functools import lru_cache
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from PIL import Image
from sentence_transformers import SentenceTransformer
from lightgbm import LGBMRegressor

from storage import load_artifact, save_artifact

ROOT = Path(__file__).resolve().parent
CLIP_ID = "sentence-transformers/clip-ViT-B-32"

# GourmetShareMap/Services/Places/PlaceCategoryClassifier.swift と同じ13分類。
CATEGORIES = [
    "和食", "ラーメン・麺類", "焼肉・肉料理", "中華", "カレー", "アジア・エスニック",
    "洋食・西洋料理", "ファストフード・食堂", "カフェ・喫茶", "パン", "スイーツ",
    "居酒屋・バー", "その他",
]

MIN_RECORDS = 5  # 育成タブのLv.2(レコメンド解禁)の閾値と合わせる


@lru_cache(maxsize=1)
def clip_model() -> SentenceTransformer:
    return SentenceTransformer(CLIP_ID, device=os.getenv("CLIP_DEVICE", "cpu"))


def decode_image(record: dict) -> Image.Image:
    if record.get("image_base64"):
        raw = record["image_base64"].split(",", 1)[-1]
        data = base64.b64decode(raw, validate=True)
        if len(data) > 5 * 1024 * 1024:
            raise ValueError("image exceeds 5 MB")
        with Image.open(io.BytesIO(data)) as im:
            return im.convert("RGB")
    path = record.get("image_path")
    if not path:
        raise ValueError("image_path or image_base64 required")
    file = Path(path)
    if not file.is_absolute():
        file = ROOT / file
    with Image.open(file) as im:
        return im.convert("RGB")


def embed_records(records: list[dict]) -> dict[str, np.ndarray]:
    """1リクエスト内で画像IDごとに1回だけ埋め込みを計算する。"""
    photos: dict[str, Image.Image] = {}
    for rec in records:
        image_id = str(rec["image_id"])
        if image_id not in photos:
            photos[image_id] = decode_image(rec)
    if not photos:
        return {}
    ids = list(photos)
    arr = clip_model().encode(
        list(photos.values()), batch_size=16, normalize_embeddings=True,
        convert_to_numpy=True, show_progress_bar=False,
    )
    return dict(zip(ids, arr))


def user_history_features(history: list[dict], target: dict, embeddings: dict) -> dict:
    """評価済みの店だけがプロフィールに入る。targetは呼び出し側で除外しておくこと。"""
    feats = {
        "hist_count": len(history), "hist_avg": 3.0, "cat_hist_avg": 3.0,
        "liked_image_similarity": 0.0, "disliked_image_similarity": 0.0,
    }
    if not history:
        return feats
    ratings = np.array([float(h["rating"]) for h in history])
    feats["hist_avg"] = float(ratings.mean())
    matching = [float(h["rating"]) for h in history if h["category"] == target["category"]]
    feats["cat_hist_avg"] = float(np.mean(matching)) if matching else feats["hist_avg"]
    q = embeddings[str(target["image_id"])]
    for name, predicate in [
        ("liked_image_similarity", lambda r: r >= 4),
        ("disliked_image_similarity", lambda r: r <= 2),
    ]:
        emb = [embeddings[str(h["image_id"])] for h in history if predicate(float(h["rating"]))]
        if emb:
            mean_emb = np.mean(emb, axis=0)
            norm = np.linalg.norm(mean_emb)
            feats[name] = float(q @ (mean_emb / norm)) if norm > 0 else 0.0
    return feats


def featurize(target: dict, history: list[dict], embeddings: dict) -> dict:
    result = {
        "google_rating": float(target["google_rating"]),
        "review_count_log": float(np.log1p(int(target["review_count"]))),
        "price_level": float(target["price_level"]),
    }
    result.update({f"cat_{i}": float(target["category"] == c) for i, c in enumerate(CATEGORIES)})
    result.update(user_history_features(history, target, embeddings))
    vec = embeddings[str(target["image_id"])]
    result.update({f"clip_{i:03d}": float(v) for i, v in enumerate(vec)})
    return result


def validate_record(r: dict, rated: bool) -> None:
    required = ["place_id", "image_id", "category", "price_level", "google_rating", "review_count"]
    if rated:
        required += ["user_id", "rating", "rated_at"]
    missing = [x for x in required if x not in r]
    if missing:
        raise ValueError(f"missing fields: {missing}")
    if r["category"] not in CATEGORIES:
        raise ValueError("category must be one of " + ", ".join(CATEGORIES))
    if rated and not 1 <= float(r["rating"]) <= 5:
        raise ValueError("rating must be 1..5")
    if not (r.get("image_path") or r.get("image_base64")):
        raise ValueError("image_path or image_base64 required")


def _fit(frame: pd.DataFrame, y: list[float]) -> LGBMRegressor:
    # 1ユーザーあたり5〜数十件という少データ前提のため、木の複雑さをデータ量に合わせて絞る。
    n = len(y)
    model = LGBMRegressor(
        n_estimators=min(150, max(20, n * 6)),
        learning_rate=0.1,
        num_leaves=max(2, min(15, n)),
        max_depth=4,
        min_child_samples=1,
        min_split_gain=0.0,
        verbosity=-1,
        random_state=42,
        n_jobs=1,
    )
    model.fit(frame, y)
    return model


def _expanding_features(user_records: list[dict], embeddings: dict) -> tuple[pd.DataFrame, list[float]]:
    """各レコードを、本人の「それより前の評価」だけを履歴として特徴量化する。"""
    X, y = [], []
    for i, r in enumerate(user_records):
        X.append(featurize(r, user_records[:i], embeddings))
        y.append(float(r["rating"]))
    return pd.DataFrame(X).fillna(0), y


def _loocv_mean_abs_error(user_records: list[dict], embeddings: dict) -> float | None:
    """5-Foldは1人あたりのデータが少ないと不安定なため、LOOCVで評価する。"""
    if len(user_records) < 3:
        return None
    errors = []
    for i in range(len(user_records)):
        train_records = user_records[:i] + user_records[i + 1:]
        X_train, y_train = _expanding_features(train_records, embeddings)
        held_out = user_records[i]
        x_held = pd.DataFrame([featurize(held_out, user_records[:i], embeddings)])
        x_held = x_held.reindex(columns=X_train.columns, fill_value=0)
        model = _fit(X_train, y_train)
        pred = float(np.clip(model.predict(x_held)[0], 1, 5))
        errors.append(abs(pred - float(held_out["rating"])))
    return float(np.mean(errors))


def train_user(user_id: str, records: list[dict]) -> dict:
    if len(records) < MIN_RECORDS:
        raise ValueError(f"need >={MIN_RECORDS} rating records for this user (has {len(records)})")
    for r in records:
        validate_record(r, rated=True)
        if str(r["user_id"]) != str(user_id):
            raise ValueError("records must all belong to user_id")
    user_records = sorted(records, key=lambda x: x["rated_at"])
    embeddings = embed_records(user_records)
    frame, y = _expanding_features(user_records, embeddings)
    model = _fit(frame, y)
    mean_abs_error = _loocv_mean_abs_error(user_records, embeddings)
    bundle = {"model": model, "columns": list(frame.columns), "clip_id": CLIP_ID}
    model_path = save_artifact(user_id, bundle)
    return {
        "user_id": user_id,
        "trained_records": len(y),
        "feature_count": len(frame.columns),
        "mean_abs_error": mean_abs_error,
        "model_path": model_path,
    }


def has_model(user_id: str) -> bool:
    return load_artifact(user_id) is not None


def predict_for_user(user_id: str, history: list[dict], candidates: list[dict]) -> list[dict]:
    bundle = load_artifact(user_id)
    if bundle is None:
        raise FileNotFoundError(f"No model for user {user_id}: call /train first")
    if not candidates:
        return []
    for r in history:
        validate_record(r, rated=True)
    for r in candidates:
        validate_record(r, rated=False)
    embeddings = embed_records(history + candidates)
    X = pd.DataFrame([featurize(c, history, embeddings) for c in candidates])
    X = X.reindex(columns=bundle["columns"], fill_value=0)
    values = np.clip(bundle["model"].predict(X), 1, 5)
    result = [
        {
            "place_id": str(c["place_id"]),
            "name": c.get("name"),
            "category": c.get("category"),
            "predicted_rating": round(float(v), 2),
        }
        for c, v in zip(candidates, values)
    ]
    return sorted(result, key=lambda x: x["predicted_rating"], reverse=True)
