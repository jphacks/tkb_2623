"""Immutable model generations. Publishing a generation is a separate DB transaction."""
from __future__ import annotations

import io
import os
import re
import tempfile
from pathlib import Path
from uuid import uuid4

import joblib

BUCKET = os.getenv("MODEL_BUCKET")
LOCAL_DIR = Path(__file__).resolve().parent / "artifacts"


def component(value: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", value):
        raise ValueError("invalid model identifier")
    return value


def _gcs_bucket():
    from google.cloud import storage
    return storage.Client().bucket(BUCKET)


def artifact_key(user_id: str, version: str | None = None, prefix: str = "models") -> str:
    if prefix not in ("models", "manual-tests"):
        raise ValueError("invalid artifact prefix")
    suffix = f"{component(version)}/" if version else ""
    return f"{prefix}/{component(user_id)}/{suffix}model.joblib"


def save_artifact(user_id: str, bundle: dict, version: str | None = None,
                  output_dir: Path | None = None, *, prefix: str = "models") -> str:
    version = version or uuid4().hex
    key = artifact_key(user_id, version, prefix)
    buf = io.BytesIO()
    joblib.dump(bundle, buf)
    if BUCKET and output_dir is None:
        buf.seek(0)
        _gcs_bucket().blob(key).upload_from_file(
            buf, content_type="application/octet-stream", if_generation_match=0,
        )
        return f"gs://{BUCKET}/{key}"
    path = (output_dir or LOCAL_DIR) / key
    path.parent.mkdir(parents=True, exist_ok=True)
    # Avoid exposing partially-written models to concurrent readers.
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as tmp:
        tmp.write(buf.getvalue())
        temp_path = Path(tmp.name)
    os.replace(temp_path, path)
    return str(path)


def load_artifact(user_id: str, version: str | None = None,
                  output_dir: Path | None = None) -> dict | None:
    key = artifact_key(user_id, version)
    if BUCKET and output_dir is None:
        from google.api_core.exceptions import NotFound
        try:
            data = _gcs_bucket().blob(key).download_as_bytes()
        except NotFound:
            return None
        return joblib.load(io.BytesIO(data))
    path = (output_dir or LOCAL_DIR) / key
    if not path.exists():
        return None
    return joblib.load(path)


def serialized_size(bundle: dict) -> int:
    buf = io.BytesIO()
    joblib.dump(bundle, buf)
    return buf.tell()
