"""モデルの保存先。Cloud Runはステートレスなので本番はGCS、ローカル実行時はファイルにフォールバック。"""
from __future__ import annotations

import io
import os
from pathlib import Path

import joblib

BUCKET = os.getenv("MODEL_BUCKET")
LOCAL_DIR = Path(__file__).resolve().parent / "artifacts"


def _blob_path(user_id: str) -> str:
    return f"models/{user_id}/model.joblib"


def _gcs_bucket():
    from google.cloud import storage

    return storage.Client().bucket(BUCKET)


def save_artifact(user_id: str, bundle: dict) -> str:
    buf = io.BytesIO()
    joblib.dump(bundle, buf)
    buf.seek(0)
    if BUCKET:
        blob = _gcs_bucket().blob(_blob_path(user_id))
        blob.upload_from_file(buf, content_type="application/octet-stream")
        return f"gs://{BUCKET}/{_blob_path(user_id)}"
    LOCAL_DIR.mkdir(parents=True, exist_ok=True)
    path = LOCAL_DIR / f"{user_id}.joblib"
    path.write_bytes(buf.getvalue())
    return str(path)


def load_artifact(user_id: str) -> dict | None:
    if BUCKET:
        blob = _gcs_bucket().blob(_blob_path(user_id))
        if not blob.exists():
            return None
        buf = io.BytesIO()
        blob.download_to_file(buf)
        buf.seek(0)
        return joblib.load(buf)
    path = LOCAL_DIR / f"{user_id}.joblib"
    if not path.exists():
        return None
    return joblib.load(path)
