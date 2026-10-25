# 料理写真の特徴抽出

記録写真から料理の特徴（形式・系統・部品の属性・共通の属性）を Gemini API で抽出し、
写真ごとに `public.image.dish_features` へ JSON で保存します。仕様は「料理写真の特徴抽出スキーマ（高解像度版）」を参照。

## 全体の流れ

```
[アプリ] 記録を保存（RecordStore.save）
   1. store を保存（カテゴリは登録画面でユーザーが選択）
   2. 写真を1枚ずつ ImageRepository.uploadImage → image 行が追加される
        │ Database Webhook（image の INSERT）
        ▼
[Edge Function: analyze-dish]
   3. image.dish_features_status を pending にする
   4. store.category と写真を取得
   5. そのカテゴリの定義を渡し、Gemini で 形式・系統・parts・common・caption を抽出（1回の呼び出し）
   6. image.dish_features に結果を保存し、dish_features_status を done（失敗時は failed）にする
```

- アプリ側の保存処理は変更しません。写真が `image` に入ると自動で解析が始まります。
- 解析に失敗しても記録の保存は失敗しません（`dish_features_status = failed` が残るだけ）。失敗理由は Edge Function のログに出ます。
- 同じお店を再訪問した場合、写真は既存の store に追加されるので、写真ごとに解析されます。
- 写真を削除すると、その行と一緒に解析結果も消えます。

## 現在の実装状況

| 部分 | ファイル | 状態 |
|---|---|---|
| 保存先カラム | `migrations/20261025020000_image_dish_features.sql` | 実装済み |
| Edge Function（Webhook 受付 → 解析 → 保存） | `functions/analyze-dish/index.ts` | 実装済み |
| Gemini 呼び出し・プロンプト・JSON Schema | `functions/analyze-dish/gemini.ts` / `schema.ts` | 実装済み |
| JSON のテンプレート（形式・系統・部品・選択肢） | `functions/analyze-dish/vocab/v1.ts` | 実装済み（全13カテゴリ） |
| Database Webhook の設定 | ダッシュボード | 下記の手順で設定 |
| アプリで解析結果を読む・表示する | `GourmetShareMap/` | 対象外（今は保存まで） |

## 判定の流れ

1. **カテゴリ:** `store.category`（登録画面でユーザーが選んだ13カテゴリのどれか）をそのまま使う。Gemini では判定しない
2. **形式・系統:** そのカテゴリの候補から Gemini が選ぶ
3. **部品の属性:** そのカテゴリの部品表で `parts` を記述する
4. **保存:** 写真1枚の結果をその `image` 行に保存する

- 写真の主役の料理1つだけを記述する。ほかの料理（餃子・ライスなど）は `common.surroundings.side` に入れる
- 値は定義済みの選択肢・段階評価から選ぶ（Gemini の構造化出力で型を固定する）
- 写っていない・判断できない項目は `null`。「なし」は写っていて無いと確認できる場合だけ使う（`vocab/v1.ts` の `EXTRACTION_RULES`）
- 横断軸（脂の強さ・味の濃さなど）と確信度は扱わない
- カテゴリ「その他」は部品表を持たない。`format` / `lineage` / `parts` は `null` で、`common` と `caption` だけ出力する

## 保存形式

| カラム | 内容 |
|---|---|
| `dish_features` | 下の JSON。解析前・失敗時は `null` |
| `dish_features_status` | `null`（未解析）/ `pending`（解析中）/ `done` / `failed` |

```json
{
  "schema_version": "v1",
  "model": "gemini-3.5-flash-lite",
  "features": {
    "category": "ラーメン・麺類",
    "format": "汁あり",
    "lineage": "背脂醤油",
    "parts": {
      "soup": { "base": "醤油", "turbidity": 2, "color_depth": 4, "viscosity": "さらさら" },
      "oil": { "types": ["背脂粒"], "amount": 3, "fat_grain": "細かい" },
      "noodle": null,
      "...": "カテゴリごとに異なる"
    },
    "common": {
      "overall": { "volume": 3, "plating": "素朴", "...": "..." },
      "vessel": { "material": "磁器", "style": "和（染付・土物）", "shape": "丼" },
      "surroundings": { "side": ["餃子"], "...": "..." }
    },
    "caption": "澄んだ醤油スープに細かい背脂と黒胡椒。"
  }
}
```

`features` の項目と選択肢は `functions/analyze-dish/vocab/v1.ts` で定義する。

## 未対応・要相談

- **処理時間・再試行:** Gemini は1枚に数十秒かかることがある（混雑時は 503、無料枠の上限を超えると 429 で失敗する）。
  Webhook には先に 202 を返し、解析は `EdgeRuntime.waitUntil` で裏で続けるが、Edge Function の実行時間の上限
  （Free 150秒 / 有料 400秒）を超えると `pending` のまま残る。`pending` / `failed` / `null` の行を再解析する仕組みは今後の課題。
- **カテゴリの変更:** 記録の編集画面でカテゴリを変えても、既存の写真は再解析されない（`features.category` は解析時の値のまま）。
- **撮影時間帯:** 写真の撮影時刻は `RecordPhoto.takenAt` にあるが `image` テーブルに保存されていないため、扱っていない。
- **Gemini 無料枠:** 送ったデータ（料理写真）が Google のサービス改善に使われる場合がある。
  上限はプロジェクト単位で数えられる。利用前に最新の利用規約・上限を確認すること。

## 設定手順

API キーはアプリや git に置かず、Edge Function の Secret にだけ置きます。

| 名前 | 内容 |
|---|---|
| `GEMINI_API_KEY` | Google AI Studio（https://aistudio.google.com/）で発行した API キー |
| `GEMINI_MODEL` | 使うモデル（任意。空なら `gemini-3.5-flash-lite`） |
| `ANALYZE_DISH_WEBHOOK_SECRET` | Webhook と Edge Function で共有する合言葉。長いランダム文字列 |

### 1. カラムの追加

ダッシュボード > SQL Editor で `migrations/20261025020000_image_dish_features.sql` を実行します。

### 2. Edge Function のデプロイ

Database Webhook は JWT を付けずに呼ぶため、**必ず `--no-verify-jwt` を付けてデプロイ**します
（付け忘れると Webhook が関数に届く前に 401 で拒否されます）。呼び出し元は `x-webhook-secret` で確認します。

```bash
supabase login
supabase functions deploy analyze-dish --project-ref <プロジェクトID> --no-verify-jwt
supabase secrets set --project-ref <プロジェクトID> \
  GEMINI_API_KEY=... ANALYZE_DISH_WEBHOOK_SECRET=...
```

ダッシュボードの **Edge Functions → Secrets** から登録しても同じです。

### 3. Database Webhook

ダッシュボードの **Database → Webhooks** で作成します。

- Table: `public.image` / Events: `Insert`
- Type: Supabase Edge Functions → `analyze-dish`（Method: POST）
- HTTP Headers: `x-webhook-secret: <ANALYZE_DISH_WEBHOOK_SECRET と同じ値>`

### 4. 動作確認

アプリで写真付きの記録を保存し、SQL Editor で結果を確認します。

```sql
select id, dish_features_status, dish_features->'features'->>'caption' as caption, created_at
  from public.image
 order by created_at desc
 limit 10;
```

`pending` のまま、または `failed` の場合は **Edge Functions → analyze-dish → Logs** を確認します。
Webhook が届いていない（`null` のまま）場合は、`net._http_response` で Webhook の応答を確認できます。

### ローカルで動かす場合

`supabase functions serve` には `supabase init` 済みのプロジェクト（`supabase/config.toml`）が必要です（このリポジトリには未作成）。

```bash
cp supabase/functions/.env.example supabase/functions/.env.local
# .env.local を開いて値を入れる（git には上がらない）
supabase functions serve analyze-dish --no-verify-jwt --env-file supabase/functions/.env.local
```
