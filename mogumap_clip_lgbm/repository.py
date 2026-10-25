"""Small Supabase REST adapter for the server/Job. No credentials in the iOS app."""
from __future__ import annotations

import os
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import quote

import requests

from policy import MAX_RECORDS


class Repository:
    def __init__(self, url: str | None = None, key: str | None = None):
        self.url = (url or os.environ["SUPABASE_URL"]).rstrip("/")
        key = key or os.environ["SUPABASE_SERVICE_ROLE_KEY"]
        self.headers = {"apikey": key, "Authorization": f"Bearer {key}"}

    def request(self, method: str, path: str, **kwargs):
        response = requests.request(method, self.url + path, headers=self.headers,
                                    timeout=(5, 45), **kwargs)
        response.raise_for_status()
        return response

    def rpc(self, name: str, **params):
        return self.request("POST", f"/rest/v1/rpc/{name}", json=params).json()

    def status(self, user_id: str) -> dict | None:
        rows = self.request("GET", "/rest/v1/ai_model_status", params={
            "user_id": f"eq.{user_id}", "select": "*", "limit": "1",
        }).json()
        return rows[0] if rows else None

    def history(self, user_id: str) -> list[dict]:
        from history import store_record, valid_history
        stores = []
        for offset in range(0, MAX_RECORDS + 1, 500):
            page = self.request("GET", "/rest/v1/store", params={
                "user_id": f"eq.{user_id}", "reputation": "not.is.null",
                "select": "id,category,reputation,price_level,google_rating,review_count,created_at,image(id,image,created_at)",
                "order": "id.asc", "offset": str(offset), "limit": "500",
            }).json()
            stores.extend(page)
            if len(stores) > MAX_RECORDS:
                raise ValueError("history exceeds supported record count")
            if len(page) < 500:
                break

        def download(store):
            photos = sorted(store.get("image") or [], key=lambda x: (x["created_at"], x["id"]))
            if not photos:
                return None
            photo = photos[0]
            response = self.request("GET", "/storage/v1/object/authenticated/record-images/"
                                    + quote(photo["image"], safe="/"))
            return store_record(store, photo, response.content, user_id)

        # A transient download failure fails the job instead of advancing its baseline.
        with ThreadPoolExecutor(max_workers=8) as pool:
            rows = [r for r in pool.map(download, stores) if r is not None]
        return valid_history(rows, user_id)

    def repair(self, user_id: str):
        self.rpc("ai_mark_dirty", p_user_id=user_id, p_repair=True)
