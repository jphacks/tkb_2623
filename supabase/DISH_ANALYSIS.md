# 料理写真の特徴抽出

記録写真から料理の特徴（形式・系統・部品の属性・共通の属性）を Gemini API で抽出し、
`public.dish_analysis` に JSON で保存します。仕様は「料理写真の特徴抽出スキーマ（高解像度版）」を参照。

## 全体の流れ

```
[アプリ] 記録を保存（RecordStore.save）
   1. store を保存（カテゴリは登録画面でユーザーが選択）
   2. 写真を1枚ずつ ImageRepository.uploadImage → image 行が追加される
        │ Database Webhook（image の INSERT）
        ▼
[Edge Function: analyze-dish]
   3. dish_analysis に status = pending の行を作る
   4. store.category と写真を取得
   5. そのカテゴリの定義を渡し、Gemini で 形式・系統・parts・common・caption を抽出（1回の呼び出し）
   6. dish_analysis を done（失敗時は failed）に更新
```

- アプリ側の保存処理は変更しません。写真が `image` に入ると自動で解析が始まります。
- 解析に失敗しても記録の保存は失敗しません（`dish_analysis.status = failed` が残るだけ）。
- 同じお店を再訪問した場合、写真は既存の store に追加されるので、写真ごとに解析されます。
- 写真を削除すると解析結果も消えます（`on delete cascade`）。

## 現在の実装状況

| 部分 | ファイル | 状態 |
|---|---|---|
| 保存先テーブル | `migrations/20261025000000_dish_analysis.sql` | 実装済み |
| Edge Function（Webhook 受付 → 解析 → 保存） | `functions/analyze-dish/index.ts` | 実装済み（未実行） |
| Gemini 呼び出し・プロンプト・JSON Schema | `functions/analyze-dish/gemini.ts` / `schema.ts` | 実装済み（未実行） |
| JSON のテンプレート（形式・系統・部品・選択肢） | `functions/analyze-dish/vocab/v1.ts` | 実装済み（全13カテゴリ） |
| Database Webhook の設定 | ダッシュボード | 未設定 |
| アプリで解析結果を読む Model / Repository | `GourmetShareMap/` | 未実装 |

## 判定の流れ

1. **カテゴリ:** `store.category`（登録画面でユーザーが選んだ13カテゴリのどれか）をそのまま使う。Gemini では判定しない
2. **形式・系統:** そのカテゴリの候補から Gemini が選ぶ
3. **部品の属性:** そのカテゴリの部品表で `parts` を記述する
4. **保存:** 写真1枚＝1行で `dish_analysis` に保存する

- 写真の主役の料理1つだけを記述する。ほかの料理（餃子・ライスなど）は `common.side` に入れる
- 値は定義済みの選択肢・段階評価から選ぶ（Gemini の構造化出力で型を固定する）
- 写っていない・判断できない項目は `null`。「なし」は写っていて無いと確認できる場合だけ使う（`vocab/v1.ts` の `EXTRACTION_RULES`）
- 横断軸（脂の強さ・味の濃さなど）と確信度は扱わない
- カテゴリ「その他」は部品表を持たない。`format` / `lineage` / `parts` は `null` で、`common` と `caption` だけ出力する

## 保存形式（`dish_analysis.result`）

```json
{
  "category": "ラーメン・麺類",
  "format": "汁あり",
  "lineage": "背脂醤油",
  "parts": {
    "soup": { "base": "醤油", "turbidity": 2, "color_depth": 4, "viscosity": "さらさら" },
    "oil": { "types": ["背脂粒"], "amount": 3, "fat_grain": "細かい" },
    "noodle": null,
    "...": "カテゴリごとに異なる"
  },
  "common": { "volume": 3, "plating": "素朴", "vessel": { "material": "磁器", "style": "和（染付・土物）", "shape": "丼" }, "...": "全カテゴリ共通" },
  "caption": "澄んだ醤油スープに細かい背脂と黒胡椒。"
}
```

項目と選択肢は `functions/analyze-dish/vocab/v1.ts` で定義する。
`category` / `format` / `lineage` は列にも同じ値を持つ（検索・集計用）。

## 未対応・要相談

- **処理時間:** Gemini は1枚に数十秒〜100秒以上かかることがある（混雑時は 503 で失敗することもある）。
  Webhook には先に 202 を返し、解析は `EdgeRuntime.waitUntil` で裏で続ける。Edge Function の実行時間の上限を
  超えると `pending` のまま残るため、残った行を再解析する仕組み（再試行）は今後の課題。

- **撮影時間帯（`common.time_of_day`）:** 写真の撮影時刻は `RecordPhoto.takenAt` にあるが、
  `image` テーブルに保存されていないため現在は `null`。入れるには `image` に `taken_at` 列を追加し、
  `ImageRepository.uploadImage` で渡す必要がある（写真保存の担当と要相談）。
- **Gemini 無料枠:** 送ったデータ（料理写真）が Google のサービス改善に使われる場合がある。
  上限はプロジェクト単位で数えられる。利用前に最新の利用規約・上限を確認すること。

## Secret（API キー）の設定

API キーはアプリや git に置かず、Edge Function の Secret にだけ置きます。

| 名前 | 内容 |
|---|---|
| `GEMINI_API_KEY` | Google AI Studio（https://aistudio.google.com/）で発行した API キー |
| `GEMINI_MODEL` | 使うモデル（任意。空なら `gemini-3.1-flash-lite`） |
| `ANALYZE_DISH_WEBHOOK_SECRET` | Webhook と Edge Function で共有する合言葉。長いランダム文字列 |

### ローカル

```bash
cp supabase/functions/.env.example supabase/functions/.env.local
# .env.local を開いて値を入れる（git には上がらない）
supabase functions serve analyze-dish --env-file supabase/functions/.env.local
```

`supabase functions serve` には `supabase init` 済みのプロジェクト（`supabase/config.toml`）が必要です。

### 本番

ダッシュボードの **Edge Functions → Secrets** に上の2つを登録します。コマンドの場合:

```bash
supabase secrets set GEMINI_API_KEY=... ANALYZE_DISH_WEBHOOK_SECRET=...
```

### Database Webhook

ダッシュボードの **Database → Webhooks** で作成します。

- Table: `public.image` / Events: `Insert`
- Type: Supabase Edge Functions → `analyze-dish`
- HTTP Headers: `x-webhook-secret: <ANALYZE_DISH_WEBHOOK_SECRET と同じ値>`
