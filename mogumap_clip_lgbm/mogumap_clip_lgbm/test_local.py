import json
from pathlib import Path
from ml import train, predict

root = Path(__file__).resolve().parent
rows = json.loads((root / 'data/train.json').read_text(encoding='utf-8'))
print('TRAIN:', train(rows))
history = [r for r in rows if r['user_id'] == 'demo_user_0'][:8]
places = json.loads((root / 'data/places.json').read_text(encoding='utf-8'))
used = {r['place_id'] for r in history}
candidates = [p for p in places if p['place_id'] not in used][:5]
print('PREDICT:', predict(history, candidates))
