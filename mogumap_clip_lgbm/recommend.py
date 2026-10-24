"""フリーテキスト→検索条件抽出(Vertex AI Gemini)→実店舗検索(Google Places API New)。

幻覚対策として、LLMには検索条件(カテゴリ/キーワード)だけを抽出させ、店名は生成させない。
実店舗はGoogle Places Text Searchで取得する。
"""
from __future__ import annotations

import base64
import json
import os

import requests
from google import genai
from google.genai import types

from ml import CATEGORIES

PROJECT = os.getenv("GOOGLE_CLOUD_PROJECT")
# asia-northeast1/us-central1リージョンにはgemini-3.8-flashが無く、globalエンドポイントのみ利用可能だった(2026-10-24確認)。
LOCATION = os.getenv("VERTEX_LOCATION", "global")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-3.8-flash")
PLACES_API_KEY = os.getenv("PLACES_API_KEY")

_CONDITION_SCHEMA = {
    "type": "object",
    "properties": {
        "category": {"type": "string", "enum": CATEGORIES + ["指定なし"]},
        "keywords": {"type": "array", "items": {"type": "string"}},
        "search_query": {"type": "string"},
    },
    "required": ["category", "keywords", "search_query"],
}

_PRICE_LEVEL_MAP = {
    "PRICE_LEVEL_FREE": 1,
    "PRICE_LEVEL_INEXPENSIVE": 1,
    "PRICE_LEVEL_MODERATE": 2,
    "PRICE_LEVEL_EXPENSIVE": 3,
    "PRICE_LEVEL_VERY_EXPENSIVE": 4,
}


def extract_conditions(free_text: str) -> dict:
    client = genai.Client(vertexai=True, project=PROJECT, location=LOCATION)
    prompt = (
        "ユーザーが食事に行きたい場所・食べたいものを自由に書いた文章から、"
        "検索に使う条件だけを抽出してください。店名は絶対に創作しないこと。\n"
        f'カテゴリは次のいずれかから最も近いものを1つ選ぶ: {", ".join(CATEGORIES)}。'
        "当てはまらなければ「指定なし」。\n"
        'search_queryはGoogle Places検索にそのまま使える日本語の短いクエリ(例: "静かな個室の和食")。\n'
        f"ユーザーの文章: {free_text}"
    )
    response = client.models.generate_content(
        model=GEMINI_MODEL,
        contents=prompt,
        config=types.GenerateContentConfig(
            response_mime_type="application/json",
            response_schema=_CONDITION_SCHEMA,
        ),
    )
    return json.loads(response.text)


def _photo_to_base64(photo_name: str) -> str | None:
    url = f"https://places.googleapis.com/v1/{photo_name}/media"
    resp = requests.get(url, params={"maxWidthPx": 400, "key": PLACES_API_KEY}, timeout=10)
    if resp.status_code != 200:
        return None
    return base64.b64encode(resp.content).decode("ascii")


def search_candidates(conditions: dict, lat: float, lng: float, max_results: int = 10) -> list[dict]:
    query = conditions.get("search_query") or " ".join(conditions.get("keywords", [])) or "飲食店"
    body = {
        "textQuery": query,
        "languageCode": "ja",
        "pageSize": max_results,
        "locationBias": {
            "circle": {"center": {"latitude": lat, "longitude": lng}, "radius": 3000.0},
        },
    }
    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": PLACES_API_KEY,
        "X-Goog-FieldMask": (
            "places.id,places.displayName,places.primaryType,places.types,"
            "places.rating,places.userRatingCount,places.priceLevel,places.photos"
        ),
    }
    resp = requests.post(
        "https://places.googleapis.com/v1/places:searchText",
        json=body, headers=headers, timeout=15,
    )
    resp.raise_for_status()
    places = resp.json().get("places", [])
    category = conditions.get("category") if conditions.get("category") in CATEGORIES else "その他"
    candidates = []
    for p in places[:max_results]:
        photos = p.get("photos") or []
        if not photos:
            continue  # CLIP特徴量の計算に画像が必須
        image_b64 = _photo_to_base64(photos[0]["name"])
        if not image_b64:
            continue
        candidates.append({
            "place_id": p["id"],
            "image_id": photos[0]["name"],
            "image_base64": image_b64,
            "name": p.get("displayName", {}).get("text", ""),
            "category": category,
            "price_level": _PRICE_LEVEL_MAP.get(p.get("priceLevel"), 2),
            "google_rating": p.get("rating", 3.5),
            "review_count": p.get("userRatingCount", 0),
        })
    return candidates
