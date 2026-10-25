"""推薦・学習で共有する境界条件。iOSの成長レベルとは独立。"""
MIN_RECOMMEND_RECORDS = 0
MIN_TRAIN_RECORDS = 6
MIN_ML_RECOMMEND_RECORDS = 6
RETRAIN_NEW_RECORDS = 5
MAX_RECORDS = 2000
POLICY_VERSION = "personal-v2"

CATEGORIES = [
    "和食", "ラーメン・麺類", "焼肉・肉料理", "中華", "カレー", "アジア・エスニック",
    "洋食・西洋料理", "ファストフード・食堂", "カフェ・喫茶", "パン", "スイーツ",
    "居酒屋・バー", "その他",
]


def training_due(records: list[dict], status: dict | None, force: bool = False) -> bool:
    if len(records) < MIN_TRAIN_RECORDS:
        return False
    if force or not status or status.get("training_policy") != POLICY_VERSION:
        return True
    previous = set(status.get("trained_store_ids") or [])
    return len({str(r["place_id"]) for r in records} - previous) >= RETRAIN_NEW_RECORDS


def model_available(status: dict | None) -> bool:
    return bool(status and status.get("training_policy") == POLICY_VERSION
                and status.get("model_version")
                and status.get("record_count", 0) >= MIN_TRAIN_RECORDS)
