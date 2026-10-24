"""Create synthetic colored 'food-like' patterns; NEVER use for quality claims."""
import json
import math
import random
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
random.seed(42)
CATS = ['japanese', 'italian', 'ramen', 'cafe', 'chinese', 'other']
COLORS = ['#dbb679', '#b8d36f', '#f0b36e', '#b89b70', '#cf715b', '#9f92bb']

def main():
    folder = ROOT / 'data' / 'images'
    folder.mkdir(parents=True, exist_ok=True)
    places = []
    for j in range(48):
        c = j % len(CATS)
        name = f'demo_{j:03d}'
        im = Image.new('RGB', (224, 224), '#eee6dc')
        d = ImageDraw.Draw(im)
        d.ellipse((15, 15, 209, 209), fill='#fbfbf6', outline='#96928c', width=6)
        d.ellipse((32, 32, 192, 192), fill=COLORS[c], outline='#bcb0a0', width=2)
        for k in range(6):
            a = k * math.pi / 3 + j * .15
            x, y = 112 + 55 * math.cos(a), 112 + 55 * math.sin(a)
            d.ellipse((x-12, y-12, x+12, y+12), fill=COLORS[(c+k+1) % len(CATS)])
        im.save(folder / (name + '.png'))
        places.append({'place_id': name, 'image_id': name,
                       'image_path': f'data/images/{name}.png', 'category': CATS[c],
                       'price_level': 1 + (j % 4),
                       'google_rating': round(3.1 + (j % 18) * .095, 2),
                       'review_count': 20 + ((j * 37) % 400)})
    rows = []
    for u in range(12):
        order = list(range(48))
        random.Random(1000 + u).shuffle(order)
        for index, j in enumerate(order[:32]):
            p = places[j]
            taste = 0.85 if j % 6 == u % 6 else (-0.45 if j % 6 == (u + 2) % 6 else 0)
            score = 3 + taste + (p['google_rating'] - 4) * .7 - .12 * p['price_level']
            score += random.uniform(-.7, .7)
            rows.append({**p, 'user_id': f'demo_user_{u}',
                         'rating': max(1, min(5, round(score))),
                         'rated_at': f'2026-01-{(index % 28)+1:02d}T12:00:00'})
    (ROOT / 'data').mkdir(exist_ok=True)
    (ROOT / 'data' / 'train.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')
    (ROOT / 'data' / 'places.json').write_text(json.dumps(places, indent=2), encoding='utf-8')
    print('Wrote 384 synthetic ratings, 48 artificial images.')

if __name__ == '__main__':
    main()
