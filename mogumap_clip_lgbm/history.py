"""Edge/Job/CLIに共通の履歴整形・画像検証。CLIPはロードしない。"""
from __future__ import annotations

import base64
import hashlib
import io
import json
from pathlib import Path

from PIL import Image, UnidentifiedImageError

from policy import CATEGORIES, MAX_RECORDS

ROOT = Path(__file__).resolve().parent
MAX_IMAGE_BYTES = 5 * 1024 * 1024


class InvalidImage(ValueError):
    pass


def image_bytes(record: dict) -> bytes:
    if record.get("image_base64"):
        try:
            data = base64.b64decode(record["image_base64"].split(",", 1)[-1], validate=True)
        except (ValueError, TypeError) as exc:
            raise InvalidImage("invalid image encoding") from exc
    else:
        path = Path(record["image_path"])
        data = (path if path.is_absolute() else ROOT / path).read_bytes()
    if len(data) > MAX_IMAGE_BYTES:
        raise InvalidImage("image exceeds 5 MiB")
    return data


# Cache is keyed by content, not just a mutable image ID. It stores no image bytes.
_validated: dict[str, None] = {}


def validate_image(data: bytes) -> None:
    digest = hashlib.sha256(data).hexdigest()
    if digest in _validated:
        return
    try:
        with Image.open(io.BytesIO(data)) as im:
            im.verify()
        with Image.open(io.BytesIO(data)) as im:
            im.convert("RGB").load()
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        raise InvalidImage("unreadable image") from exc
    if len(_validated) >= 4096:
        _validated.clear()
    _validated[digest] = None


def valid_history(records: list[dict], user_id: str) -> list[dict]:
    if len(records) > MAX_RECORDS:
        raise ValueError(f"history exceeds {MAX_RECORDS} records")
    result, seen = [], set()
    for row in records:
        if str(row.get("user_id")) != user_id:
            raise ValueError("history must belong to user_id")
        try:
            record = dict(row)
            if record.get("category") is None:
                record["category"] = "その他"
            if record["category"] not in CATEGORIES or not 1 <= float(record["rating"]) <= 5:
                continue
            for field, default in [("price_level", 2), ("google_rating", 3.5), ("review_count", 50)]:
                if record.get(field) is None:
                    record[field] = default
            if not (1 <= float(record["price_level"]) <= 4
                    and 0 <= float(record["google_rating"]) <= 5
                    and int(record["review_count"]) >= 0):
                continue
            place_id = str(record["place_id"])
            if place_id in seen or not record.get("image_id") or not record.get("rated_at"):
                continue
            validate_image(image_bytes(record))
        except (KeyError, ValueError, TypeError, OSError):
            continue
        seen.add(place_id)
        result.append(record)
    return sorted(result, key=lambda r: (r["rated_at"], str(r["place_id"])))


def store_record(store: dict, image: dict, data: bytes, user_id: str) -> dict:
    return {
        "user_id": user_id, "place_id": store["id"], "image_id": image["id"],
        "image_base64": base64.b64encode(data).decode("ascii"),
        "category": store.get("category"), "rating": store["reputation"],
        "rated_at": store["created_at"], "price_level": store.get("price_level"),
        "google_rating": store.get("google_rating"), "review_count": store.get("review_count"),
    }


def snapshot(records: list[dict]) -> list[dict]:
    """No image payload in the persistent manifest; capture all training input versions."""
    result = []
    for record in records:
        fields = {k: v for k, v in record.items() if k not in ("image_base64", "image_path")}
        fields["image_sha256"] = hashlib.sha256(image_bytes(record)).hexdigest()
        fields["data_version"] = hashlib.sha256(
            json.dumps(fields, sort_keys=True, ensure_ascii=False).encode()
        ).hexdigest()
        result.append(fields)
    return result
