"""Lightweight history validation for text-only recommendations (no image imports)."""
from __future__ import annotations

from policy import CATEGORIES, MAX_RECORDS


def metadata_history(records: list[dict], user_id: str) -> list[dict]:
    """Return only recommendation metadata. Never propagate image bytes or paths.

    A representative image ID is enough for the initial model-routing decision.
    Actual image validity is checked only when a published ML model is used.
    """
    if len(records) > MAX_RECORDS:
        raise ValueError(f"history exceeds {MAX_RECORDS} records")
    result, seen = [], set()
    for row in records:
        if str(row.get("user_id")) != user_id:
            raise ValueError("history must belong to user_id")
        try:
            category = row["category"] if row.get("category") is not None else "その他"
            rating = float(row["rating"])
            price = float(row["price_level"] if row.get("price_level") is not None else 2)
            google_rating = float(row["google_rating"] if row.get("google_rating") is not None else 3.5)
            reviews = int(row["review_count"] if row.get("review_count") is not None else 50)
            if (category not in CATEGORIES or not 1 <= rating <= 5 or not 1 <= price <= 4
                    or not 0 <= google_rating <= 5 or reviews < 0):
                continue
            place_id = str(row["place_id"])
            image_id, rated_at = row.get("image_id"), row.get("rated_at")
            if place_id in seen or not isinstance(image_id, str) or not image_id or not isinstance(rated_at, str) or not rated_at:
                continue
        except (KeyError, ValueError, TypeError, OverflowError):
            continue
        seen.add(place_id)
        dishes = row.get("dish_features")
        if not isinstance(dishes, list):
            dishes = []
        result.append({
            "user_id": user_id, "place_id": place_id, "image_id": image_id,
            "category": category, "rating": rating, "rated_at": rated_at,
            "price_level": price, "google_rating": google_rating, "review_count": reviews,
            "dish_features": [d for d in dishes if isinstance(d, dict)],
        })
    return sorted(result, key=lambda r: (r["rated_at"], r["place_id"]))
