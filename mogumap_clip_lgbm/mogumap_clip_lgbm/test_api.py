"""Call API end-to-end using stdlib (after server is running)."""
import json
import os
from pathlib import Path
from urllib.request import Request, urlopen

root = Path(__file__).resolve().parent
base = 'http://127.0.0.1:8000'
key = os.environ.get('MOGUMAP_API_KEY', 'dev-only-change-me')

def post(path, obj):
    req = Request(base + path, data=json.dumps(obj).encode('utf-8'), method='POST',
                  headers={'Content-Type': 'application/json', 'X-API-Key': key})
    with urlopen(req, timeout=300) as resp:
        return json.loads(resp.read())

records = json.loads((root / 'data/train.json').read_text(encoding='utf-8'))
print('Training:', post('/train', {'records': records}))
history = [r for r in records if r['user_id'] == 'demo_user_0'][:8]
places = json.loads((root / 'data/places.json').read_text(encoding='utf-8'))
used = {r['place_id'] for r in history}
candidates = [p for p in places if p['place_id'] not in used][:5]
print('Predictions:', post('/predict', {'history': history, 'candidates': candidates}))
