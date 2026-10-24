"""MoguMap prototype: frozen CLIP + LightGBM rating regression.
The toy dataset is for interface verification ONLY, not accuracy claims.
"""
from __future__ import annotations
import base64
import io
import json
import os
from functools import lru_cache
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from PIL import Image
from sentence_transformers import SentenceTransformer
from lightgbm import LGBMRegressor

ROOT = Path(__file__).resolve().parent
DATA = ROOT / 'data'
ARTIFACT = ROOT / 'artifacts' / 'model.joblib'
CLIP_ID = 'sentence-transformers/clip-ViT-B-32'
CATEGORIES = ['japanese', 'italian', 'ramen', 'cafe', 'chinese', 'other']

@lru_cache(maxsize=1)
def clip_model():
    return SentenceTransformer(CLIP_ID, device=os.getenv('CLIP_DEVICE', 'cpu'))

def decode_image(record: dict) -> Image.Image:
    if record.get('image_base64'):
        raw = record['image_base64'].split(',', 1)[-1]
        data = base64.b64decode(raw, validate=True)
        if len(data) > 5 * 1024 * 1024:
            raise ValueError('image exceeds 5 MB')
        with Image.open(io.BytesIO(data)) as im:
            return im.convert('RGB')
    path = record.get('image_path')
    if not path:
        raise ValueError('image_path or image_base64 required')
    file = Path(path)
    if not file.is_absolute():
        file = ROOT / file
    with Image.open(file) as im:
        return im.convert('RGB')

def embed_records(records: list[dict]) -> dict[str, np.ndarray]:
    """One cached embedding per distinct image identifier in one request."""
    photos = {}
    for rec in records:
        image_id = str(rec['image_id'])
        if image_id not in photos:
            photos[image_id] = decode_image(rec)
    ids = list(photos)
    arr = clip_model().encode(list(photos.values()), batch_size=16, normalize_embeddings=True,
                              convert_to_numpy=True, show_progress_bar=False)
    return dict(zip(ids, arr))

def user_history_features(history: list[dict], target: dict, embeddings: dict) -> dict:
    """Only previously rated items enter the profile; target excluded by caller."""
    feats = {'hist_count': len(history), 'hist_avg': 3.0, 'cat_hist_avg': 3.0,
             'liked_image_similarity': 0.0, 'disliked_image_similarity': 0.0}
    if not history:
        return feats
    ratings = np.array([float(h['rating']) for h in history])
    feats['hist_avg'] = float(ratings.mean())
    matching = [float(h['rating']) for h in history if h['category'] == target['category']]
    feats['cat_hist_avg'] = float(np.mean(matching)) if matching else feats['hist_avg']
    q = embeddings[str(target['image_id'])]
    for name, predicate in [('liked_image_similarity', lambda r: r >= 4),
                            ('disliked_image_similarity', lambda r: r <= 2)]:
        emb = [embeddings[str(h['image_id'])] for h in history if predicate(float(h['rating']))]
        if emb:
            mean_emb = np.mean(emb, axis=0)
            norm = np.linalg.norm(mean_emb)
            feats[name] = float(q @ (mean_emb / norm)) if norm > 0 else 0.0
    return feats

def featurize(target: dict, history: list[dict], embeddings: dict) -> dict:
    result = {
        'google_rating': float(target['google_rating']),
        'review_count_log': float(np.log1p(int(target['review_count']))),
        'price_level': float(target['price_level']),
    }
    result.update({f'cat_{c}': float(target['category'] == c) for c in CATEGORIES})
    result.update(user_history_features(history, target, embeddings))
    # Include CLIP embedding itself, not just personalized cosine scores.
    vec = embeddings[str(target['image_id'])]
    result.update({f'clip_{i:03d}': float(v) for i, v in enumerate(vec)})
    return result

def train(records: list[dict]):
    if len(records) < 30:
        raise ValueError('need >=30 rating events (prototype minimum; real training needs more)')
    by_user = {}
    for r in records:
        validate_record(r, rated=True)
        by_user.setdefault(str(r['user_id']), []).append(r)
    for user_records in by_user.values():
        user_records.sort(key=lambda x: x['rated_at'])
    embeddings = embed_records(records)
    X, y = [], []
    for user_records in by_user.values():
        for i, r in enumerate(user_records):
            # Earlier rows for THIS user only, excluding this target.
            history = user_records[:i]
            X.append(featurize(r, history, embeddings))
            y.append(float(r['rating']))
    frame = pd.DataFrame(X).fillna(0)
    model = LGBMRegressor(n_estimators=120, learning_rate=0.05, num_leaves=15,
                          min_child_samples=8, max_depth=5, verbosity=-1,
                          random_state=42, n_jobs=2)
    model.fit(frame, y)
    ARTIFACT.parent.mkdir(parents=True, exist_ok=True)
    # Only load artifacts created locally; joblib files are unsafe from untrusted parties.
    joblib.dump({'model': model, 'columns': list(frame.columns), 'clip_id': CLIP_ID}, ARTIFACT)
    return {'trained_records': len(y), 'users': len(by_user), 'feature_count': len(frame.columns),
            'model_path': str(ARTIFACT), 'warning': 'No accuracy estimate: synthetic/demo training'}

def predict(history: list[dict], candidates: list[dict]):
    if not ARTIFACT.exists():
        raise FileNotFoundError('No model: call /train first')
    if not candidates:
        return []
    for r in history:
        validate_record(r, rated=True)
    for r in candidates:
        validate_record(r, rated=False)
    all_rows = history + candidates
    embeddings = embed_records(all_rows)
    bundle = joblib.load(ARTIFACT)
    X = pd.DataFrame([featurize(c, history, embeddings) for c in candidates])
    X = X.reindex(columns=bundle['columns'], fill_value=0)
    values = np.clip(bundle['model'].predict(X), 1, 5)
    result = [{'place_id': str(c['place_id']), 'predicted_rating': round(float(v), 2)}
              for c, v in zip(candidates, values)]
    return sorted(result, key=lambda x: x['predicted_rating'], reverse=True)

def validate_record(r: dict, rated: bool):
    required = ['place_id', 'image_id', 'category', 'price_level', 'google_rating', 'review_count']
    if rated:
        required += ['user_id', 'rating', 'rated_at']
    missing = [x for x in required if x not in r]
    if missing:
        raise ValueError(f'missing fields: {missing}')
    if r['category'] not in CATEGORIES:
        raise ValueError('category must be one of ' + ', '.join(CATEGORIES))
    if rated and not 1 <= float(r['rating']) <= 5:
        raise ValueError('rating must be 1..5')
    if not (r.get('image_path') or r.get('image_base64')):
        raise ValueError('image_path or image_base64 required')

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--data', default='data/train.json')
    args = parser.parse_args()
    data_path = Path(args.data)
    print(json.dumps(train(json.loads(data_path.read_text(encoding='utf-8'))), indent=2))
