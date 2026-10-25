<<<<<<< HEAD
# MoguMap AIバックエンド — CLIP + LightGBM

MoguMap（GourmetShareMap）の「AIを育てる」機能を支えるPythonバックエンドです。本人が登録した店舗の写真・店舗情報・星評価から、**ユーザーごとのLightGBM回帰モデル**を学習し、希望と現在地に合う実店舗を予測評価順に最大3件返します。

このREADMEは、同ディレクトリ直下の現行コードとiOS・Supabase連携の実装を説明します。[REQUIREMENTS.md](REQUIREMENTS.md) は設計時の資料です。そこに記載された「5件追加ごとのWebhook学習」は現行実装にはなく、**おすすめ要求のたびに最新履歴で再学習**します。配下の `mogumap_clip_lgbm/` は旧プロトタイプで、以下の起動手順はこのREADMEと同じ階層のコードを対象にします。

## 全体構成とデータの流れ

```mermaid
sequenceDiagram
    participant App as iOS（育てる画面）
    participant DB as Supabase DB / Storage
    participant Edge as ai-recommend Edge Function
    participant API as FastAPI / Cloud Run
    participant GCS as モデル保存先（GCS）
    participant Gemini as Vertex AI Gemini
    participant Places as Google Places API (New)

    Note over App,DB: 店舗登録時
    App->>DB: 店舗情報・本人の評価・写真を保存
    Note over App,Places: おすすめ要求時
    App->>Edge: JWT + free_text + lat + lng
    Edge->>DB: 認証確認、本人の評価済み店舗と画像を取得
    Edge->>Edge: 写真をBase64化、欠損値を補完
    Edge->>API: POST /recommend（共有キー + user_id + history + 検索入力）
    API->>API: CLIP特徴抽出 → 本人のLightGBM再学習 → 交差検証
    API->>GCS: モデル・特徴列・CLIP IDを保存
    API->>Gemini: 自由文から検索条件を抽出
    Gemini-->>API: category / keywords / search_query
    API->>Places: Text Search（現在地を検索バイアスに指定）
    Places-->>API: 候補最大10件と写真情報
    API->>Places: 各候補の先頭写真を取得
    API->>GCS: 保存した本人モデルを読み込み
    API->>API: 履歴と候補を特徴量化 → 星評価を予測
    API-->>Edge: 上位3件 + conditions + model_stats
    Edge->>DB: ai_model_statusを更新
    Edge-->>App: バックエンドの応答を返却
    App->>App: 店名・予測評価・Google Mapsリンクを表示
```

店舗登録だけでは学習は走りません。`/recommend` はモデルの有無にかかわらず毎回学習します。`MODEL_BUCKET` 未設定時は、図のGCSの代わりにローカルの `artifacts/` を使います。

## 使用モデルと役割

| 要素 | 使用モデル・方式 | 役割と学習の有無 |
|---|---|---|
| 画像特徴抽出 | `sentence-transformers/clip-ViT-B-32` | 学習済みCLIPの画像エンコーダーを共有・凍結して使用。写真を正規化された512次元ベクトルへ変換し、追加学習はしない |
| 個人の好み予測 | LightGBM `LGBMRegressor` | 本人の1〜5の星評価を教師として、ユーザーごとに別の回帰モデルを学習 |
| 自由文の理解 | Vertex AI Gemini | `category`・`keywords`・`search_query` をJSONで抽出。本人の評価を学習させる処理はない |
| 候補店舗の取得 | Google Places API (New) | Text Searchと写真取得で実在する候補を集める |

Geminiのモデル名は `GEMINI_MODEL` で変更でき、コード上の既定値は `gemini-3.8-flash`、接続先の既定値は `global` です。これはリポジトリの設定値であり、実行先での利用可否は環境に依存します。

Geminiには自由文を含むプロンプトとカテゴリ定義を渡し、履歴の画像や評価は渡しません。画像はバックエンド内のCLIPで処理します。店名はGeminiに生成させず、Placesの検索結果を使用します。

## 学習アルゴリズム

### 入力と教師データ

1件の店舗記録を1学習サンプルとし、本人の `rating`（DBの `store.reputation`）を目的変数にします。Googleの公開評価 `google_rating` は入力特徴量です。他ユーザーやフレンドの履歴は学習に混ぜません。学習開始には、評価と使用可能な画像を持つ記録が最低5件必要です。

入力レコードの例（`/train` の `records`、`/recommend`・`/predict` の `history` に共通）:

```json
{
  "user_id": "demo_user_0",
  "place_id": "store-001",
  "image_id": "image-001",
  "image_path": "data/images/demo_000.png",
  "category": "和食",
  "price_level": 2,
  "google_rating": 4.1,
  "review_count": 120,
  "rating": 5,
  "rated_at": "2026-10-25T12:00:00Z"
}
```

| フィールド | 内容 |
|---|---|
| `user_id` | 学習対象ユーザー。`/train` では全記録がリクエストのユーザーと一致することを検証 |
| `place_id` | 店舗の識別子。履歴ではSupabaseの `store.id`、Places候補ではGoogle Place ID |
| `image_id` | 画像の識別子。同じ埋め込み計算内では、このIDで画像を重複排除 |
| `image_base64` / `image_path` | どちらかが必須。両方ある場合はBase64を優先。相対パスの基準はこのディレクトリ |
| `category` | 下記13分類のいずれか |
| `price_level` | 価格帯。アプリ連携では1〜4の値を使用 |
| `google_rating` | Googleの公開平均評価 |
| `review_count` | Googleのレビュー件数 |
| `rating` | 本人の評価。1〜5の範囲を検証 |
| `rated_at` | 学習時の並び順に使う日時文字列。時系列順に並ぶよう形式・タイムゾーンを揃える |

推論候補は `user_id`・`rating`・`rated_at` が不要で、表示用の `name` を追加できます。Base64画像はData URL形式も受け付け、デコード後5 MiBを超えるとエラーになります。RGBへ変換してCLIPに入力します。

カテゴリはアプリの `PlaceCategoryClassifier` に合わせた次の13種類です。

```text
和食 / ラーメン・麺類 / 焼肉・肉料理 / 中華 / カレー / アジア・エスニック /
洋食・西洋料理 / ファストフード・食堂 / カフェ・喫茶 / パン / スイーツ /
居酒屋・バー / その他
```

### 特徴量（通常533次元）

`ml.py` の `featurize()` が、店舗情報・本人の履歴・画像埋め込みを結合します。

| 特徴量 | 次元 | 計算方法 |
|---|---:|---|
| `google_rating` | 1 | Googleの公開平均評価 |
| `review_count_log` | 1 | `log(1 + review_count)` |
| `price_level` | 1 | 価格帯の数値 |
| `cat_0`〜`cat_12` | 13 | カテゴリのone-hot表現 |
| `hist_count` | 1 | 履歴件数 |
| `hist_avg` | 1 | 本人の過去評価の平均。履歴なしは3.0 |
| `cat_hist_avg` | 1 | 対象と同カテゴリの過去評価平均。該当なしは本人の全体平均 |
| `liked_image_similarity` | 1 | 評価4以上の写真の平均ベクトルを再正規化し、対象写真とのコサイン類似度を算出 |
| `disliked_image_similarity` | 1 | 評価2以下の写真について同様に算出 |
| `clip_000`〜`clip_511` | 512 | 対象写真の正規化済みCLIP画像埋め込み |

好き・苦手に該当する履歴がない場合、類似度は0です。自由文、緯度経度、店名、メモ、訪問回数、ユーザーIDそのものは回帰モデルの特徴量に含めません。

### 学習手順とパラメータ

`train_user()` は次の順で実行します。

1. 最低件数・必須フィールド・カテゴリ・評価範囲・ユーザーの一致を検証。
2. 記録を `rated_at` で昇順に並べ、画像をCLIPで埋め込み化。
3. 各記録について、その記録より前の履歴だけから履歴特徴量を作成。自分自身の正解評価をその行の履歴特徴量に含めない。
4. 全学習行でLightGBMを学習し、別途交差検証のMAEを計算。
5. モデル・特徴列の順序・CLIPモデルIDをまとめて保存。

LightGBMは複数の決定木を順次追加し、予測の誤差を補正する勾配ブースティングによる回帰です。少数データに合わせ、学習件数 `n` に応じて木の数や葉の数を抑えています。

| パラメータ | 設定値 |
|---|---|
| `n_estimators` | `min(150, max(20, n * 6))` |
| `learning_rate` | `0.1` |
| `num_leaves` | `max(2, min(15, n))` |
| `max_depth` | `4` |
| `min_child_samples` | `1` |
| `min_split_gain` | `0.0` |
| `random_state` | `42` |
| `n_jobs` | `1` |

### 評価方法

1件を除外して残りで学習するLOOCV（leave-one-out交差検証）を用い、`mean_abs_error` を返します。記録が15件を超える場合は、評価対象だけを直近15件に絞り、各回の学習には除外した1件以外の全記録を使います。

```text
MAE = mean(abs(予測評価 - 本人の実評価))
```

評価対象の履歴特徴量には、その対象より前の記録だけを使います。ただし各回のモデル学習には対象日時より後の記録も入り得るため、この数値は将来予測を厳密に検証する時系列評価ではありません。データが5件あれば動作しますが、それだけで推薦品質が保証されるわけではありません。

iOSの「好みの読み当て」は `round(max(0, 1 - MAE / 4) * 100)` で表示します。例えばMAEが0.8なら80%です。この値はMAEを表示用に換算したもので、分類の正解率や推薦の成功確率を表す値ではありません。

## 候補生成と推論

`/recommend` の再学習後は、`recommend.py` と `ml.py` が次の処理を行います。

1. Geminiで希望を構造化。例えば「静かな和食を食べたい」からカテゴリと検索クエリを抽出。
2. Places Text Searchを日本語・最大10件で実行。現在地を中心とする半径3,000mの `locationBias` を指定する。これは検索の優先範囲で、範囲内への厳密な制限ではない。
3. 各候補の先頭写真を最大幅400pxで並列取得。写真なし・写真取得失敗の候補は除外。
4. 本人の全履歴と候補写真をCLIPで特徴量化し、保存された特徴列の順序に揃えて本人モデルに入力。
5. 予測値を1〜5に収めて小数第2位に丸め、その値で降順に並べて上位3件を返す。候補がなければ空配列を返す。

候補のカテゴリにはGeminiが抽出したカテゴリを一律に設定します。「指定なし」など定義外の場合は「その他」です。Placesの店舗種別から候補ごとにカテゴリを再分類する処理はありません。候補の価格帯・公開評価・レビュー件数が欠ける場合はそれぞれ2・3.5・0で補完します。既訪問店舗を除外する処理もありません。

## 処理時間・モデル容量の概算

以下は**実測ベンチマークではなく、性能検証前の計画用の概算**です。CPU実行（1〜2 vCPU程度）、同時リクエストなし、CLIPをメモリへ読み込み済み、履歴5〜50件・候補最大10件を想定しています。CPUの種類、割り当て、PyTorchのスレッド数、画像サイズで大きく変わります。特にCloud Runのコールドスタートと外部通信は別に見積もる必要があります。

### 1店舗あたりの推論時間

「特徴量から星を予測する時間」と「写真から特徴量を作る時間」を分けて考えます。次の数値は測定結果ではなく、見積もりに置く仮の処理時間です。

| 処理 | 仮置きする時間 | 範囲に含めないもの |
|---|---|---|
| LightGBMで1店舗の星を予測 | 1〜10 ms程度 | CLIP、履歴特徴量作成、モデル読み込み、通信 |
| 写真1枚のCLIP特徴抽出 | 50〜300 ms程度 | モデル初期ロード、写真のダウンロード |
| 写真1枚から星予測までの計算 | 約0.05〜0.3秒を目安とする | 履歴画像の再計算、モデル読み込み、通信、再学習 |

LightGBMの予測は最大150本・深さ最大4の木をたどる処理で、画像特徴抽出より軽い構成です。ただし実装は候補をまとめて `predict()` し、CLIPも最大16枚ずつバッチ処理するため、上表を店舗数倍した時間と実行時間は必ずしも一致しません。特徴量作成やPython呼び出しの固定費もあります。

**API全体の時間は「1店舗の時間 × 候補件数」だけでは求められません。** `/predict` は履歴画像も毎回CLIPへ入力します。履歴を `N` 件、候補を `K` 件、`E(M)` をM枚の画像の特徴抽出時間とすると、概ね次の構成です（画像IDが重複しない場合）。

```text
T_predict ≈ モデル読み込み + E(N + K) + 履歴特徴量作成 + K件のLightGBM予測
T_recommend ≈ T_train + Gemini通信 + Places検索・写真取得 + T_predict
```

例えば履歴30件・候補10件では、推論側だけで40枚のCLIP処理が必要です。上の仮定を単純適用すると約2〜12秒で、さらに学習側で履歴30枚を処理します。`/recommend` 全体ではCLIPへ延べ `2N + K = 70` 枚を入力する計算になります。履歴画像の埋め込みを学習と推論の間で共有していないことが、この差の理由です。

### LightGBMの学習時間

最終モデルの学習だけでなく、MAE算出の交差検証でもモデルを学習します。履歴 `N` 件について、学習回数は `1 + min(N, 15)` 回です。CLIP埋め込みは `train_user()` 内で一度計算し、交差検証では再利用します。

```text
T_train ≈ E(N)
          + 全件での特徴量作成・LightGBM学習
          + min(N, 15)回の特徴量作成・LightGBM学習・評価
          + モデル保存
```

試算のため、5〜50件の範囲で「特徴量作成・LightGBM学習・評価の1回分」を仮に0.02〜0.2秒、CLIPを1枚0.05〜0.3秒と置くと、次の時間予算になります。これらの係数も未測定です。

| 本人の履歴件数 | 最終モデルの木の本数上限 | 評価込みの学習回数 | CLIP + 学習・評価の試算 |
|---|---:|---:|---:|
| 5件 | 30本 | 6回 | 約0.4〜3秒 |
| 15件 | 90本 | 16回 | 約1〜8秒 |
| 50件 | 150本 | 16回 | 約3〜20秒 |

モデル保存・初期ロード・外部通信は表の時間に含みません。LightGBM単体の最終学習は、この仮定では数十〜数百msの予算ですが、APIが返るまでにはCLIPと交差検証が加わります。50件を超える場合、特徴量作成の履歴走査も増えるため、この表からの単純な比例推定は避けてください。おすすめ要求では毎回この学習処理を行います。

### LightGBMの重みファイル容量

保存対象はニューラルネットワークの重み行列ではなく、LightGBMの決定木とメタ情報をまとめた、ユーザー別の `model.joblib` です。`joblib.dump()` は圧縮を指定していません。

- 最終モデルは最大150本の木、各木は最大15葉（内部ノード最大14個）。構造上の上限は合計2,250葉・2,100内部ノードです。実際には分割が成立せず、これより小さくなる場合があります。
- 保存ファイルにはモデル本体に加え、通常533個の特徴列名とCLIPモデルIDが入ります。交差検証用モデルは保存しません。
- **容量予算としては1ユーザーあたり数十KiB〜1MiB程度を仮置き**します。これは木の規模とシリアライズの付帯情報を考慮した概算で、実ファイルサイズの測定結果ではありません。
- この予算なら1,000ユーザーで約10MiB〜1GiB程度が目安です。画像・CLIP本体・コンテナイメージ・GCSの旧世代や管理上の付帯容量は含みません。

CLIPの学習済み重みは全ユーザー共有で、ユーザー別 `model.joblib` には含まれません。モデルファイルの容量と、CLIPを読み込むプロセスのメモリ使用量は別の指標です。

### 実測して見積もりを更新する方法

ローカル実行の手順で仮想環境を有効にしてデモデータを生成した後、次を実行すると、`train_user()` 全体の時間と保存ファイル容量を確認できます。リポジトリ内のどのディレクトリからでも実行できるよう、最初にバックエンド直下へ移動します。`MODEL_BUCKET` 未設定のローカル保存を対象にし、初回実行にはCLIPの取得・初期ロードも含まれます。

```bash
(
cd "$(git rev-parse --show-toplevel)/mogumap_clip_lgbm" || exit 1
python3 - <<'PY'
import json
import time
from pathlib import Path
from ml import train_user

rows = json.loads(Path('data/train.json').read_text())
history = [r for r in rows if r['user_id'] == 'demo_user_0']
for run in range(3):
    start = time.perf_counter()
    stats = train_user('demo_user_0', history)
    elapsed = time.perf_counter() - start
    size_kib = Path(stats['model_path']).stat().st_size / 1024
    print(f'run={run + 1} records={len(history)} train={elapsed:.3f}s size={size_kib:.1f}KiB')
PY
)
```

`ImportError: cannot import name 'train_user' from 'ml'` が出て、読み込み先が `site-packages/ml/` の場合は、別パッケージの `ml` を読み込んでいます。上のディレクトリ移動を含めて実行してください。対象はリポジトリ直下の `mogumap_clip_lgbm/ml.py` で、旧プロトタイプの `mogumap_clip_lgbm/mogumap_clip_lgbm/` ではありません。

APIの `[timing]` ログには `train`・`gemini`・`places`・`predict`・`total` の秒数が出ます。`train` はCLIP・交差検証・保存を含み、`predict` はモデル読み込みと履歴画像のCLIP処理も含みます。`total` はバックエンド内の時間で、Edge Functionによる履歴取得やアプリとの往復は含みません。候補0件の場合は `predict`・`total` のログは出ません。単一店舗のCLIP時間とLightGBM時間を分離する計測は現状ないため、それぞれの関数呼び出し前後で別途計測する必要があります。実運用の数値を記載する際は、CPU・メモリ設定、件数、コールド／ウォームを揃えて複数回測り、中央値と遅い側の値（p95など）を併記してください。

## アプリからの呼び出し

関連する実装:

| ファイル | 役割 |
|---|---|
| [GrowView.swift](../GourmetShareMap/Features/Grow/Views/GrowView.swift) | 育てる画面。登録0〜4件ではおすすめ入力UIを表示しない |
| [GrowViewModel.swift](../GourmetShareMap/Features/Grow/ViewModels/GrowViewModel.swift) | 現在地取得、通信中の状態管理、結果・エラー表示 |
| [LiveRecommendService.swift](../GourmetShareMap/Features/Grow/Services/LiveRecommendService.swift) | Edge FunctionへのHTTPリクエストと応答の変換 |
| [RecommendService.swift](../GourmetShareMap/Features/Grow/Services/RecommendService.swift) | 型定義、表示指標の換算、開発用モック |
| [ai-recommend/index.ts](../supabase/functions/ai-recommend/index.ts) | 認証、本人の履歴・画像取得、バックエンド呼び出し、学習状態の保存 |

`GrowViewModel` は既定で `LiveRecommendService` を使います。サービスはログイン中のSupabaseアクセストークンを付け、次のHTTPリクエストを送ります（タイムアウト120秒）。

```http
POST <SUPABASE_URL>/functions/v1/ai-recommend
Authorization: Bearer <ユーザーのアクセストークン>
Content-Type: application/json

{"free_text":"静かな和食を食べたい","lat":35.6812,"lng":139.7671}
```

アプリは `user_id` や学習履歴を送信しません。サービスの `records` 引数は空記録のチェックに使用し、履歴本体はEdge FunctionがDBから取得します。AIバックエンド用の共有キーもアプリには持たせません。

Edge Functionは次のように入力を組み立てます。

- JWTを `auth.getUser()` で検証し、認証済みユーザーIDを採用。
- 本人の `store` のうち `reputation` がNULLでない行と、関連する `image` を取得。
- 各店舗の関連画像配列の先頭1枚を `record-images` バケットから並列ダウンロードしてBase64化。画像配列の順序はクエリで指定していない。
- 画像のない店舗・ダウンロード失敗の店舗を除外し、有効な履歴が5件未満ならHTTP 400。
- 履歴の欠損値を `category="その他"`、`price_level=2`、`google_rating=3.5`、`review_count=50` で補完。`rated_at` には `store.created_at` を使用。
- `X-API-Key` を付けてバックエンドの `/recommend` を呼び出す。
- 成功時の `model_stats` を `ai_model_status` にupsertし、バックエンドの応答をアプリへ返す。統計保存はベストエフォート。

アプリの登録件数と、画像・評価が揃った学習可能件数は一致しない場合があります。学習状態は `fetchModelStats()` が `ai_model_status` から別途読み込みます。おすすめ取得直後に状態を再取得する処理はなく、画面表示時や記録変更時に読み直します。画面の推薦理由は自由文とカテゴリから作る定型文で、モデルの特徴量寄与を説明したものではありません。

## バックエンドAPI

`/health` 以外は `X-API-Key: <AI_BACKEND_API_KEY>` が必須です。キー未設定・不一致はHTTP 401になります。これらはEdge Functionなど信頼できるサーバーから呼ぶAPIで、バックエンド自体はSupabaseのユーザーJWTを検証しません。

| メソッド / パス | リクエスト | 応答 |
|---|---|---|
| `GET /health` | なし | `{"status":"ok"}`。外部APIやモデルの利用可否は確認しない |
| `POST /train` | `user_id`, `records`（5〜2,000件） | 学習件数、特徴量数、MAE、保存先 |
| `POST /predict` | `user_id`, `history`（最大2,000件）, `candidates`（1〜100件） | 全候補を予測評価順に並べた `predictions` |
| `POST /recommend` | `user_id`, `free_text`（1〜500文字）, `lat`, `lng`, `history`（5〜2,000件） | 最大3件の `predictions`、`conditions`、`model_stats` |

`/train` と `/predict` はデータと画像をリクエストで受け取り、Supabaseから直接読みません。`/predict` は再学習しないため、先に `/train` などでモデルを保存しておく必要があります。

`/recommend` の応答例（数値は説明用）:

```json
{
  "predictions": [
    {"place_id":"google-place-id","name":"サンプル食堂","category":"和食","predicted_rating":4.32}
  ],
  "conditions": {"category":"和食","keywords":["静か"],"search_query":"静かな和食"},
  "model_stats": {
    "user_id":"demo_user_0",
    "trained_records":5,
    "feature_count":533,
    "mean_abs_error":0.8,
    "model_path":"gs://<MODEL_BUCKET>/models/demo_user_0/model.joblib"
  }
}
```

主要なエラーは、学習データ不備・有効履歴不足が400、保存モデルなしが409、Pydanticの入力検証エラーが422です。`/train` の同一プロセス内・同一ユーザーの同時学習は409になります。このロックは `/recommend` や複数インスタンスには適用されません。外部APIの例外はすべて整形される実装ではないため、500になる場合もあります。

## 保存するデータ

| 保存先 | 内容 |
|---|---|
| Supabase `store` / `image` / Storage | 店舗情報・本人の評価・画像メタ情報・写真ファイル |
| GCS `gs://<MODEL_BUCKET>/models/{user_id}/model.joblib` | ユーザー別のLightGBMモデル、特徴列名、CLIPモデルID |
| ローカル `artifacts/{user_id}.joblib` | `MODEL_BUCKET` 未設定時のモデル保存先 |
| Supabase `ai_model_status` | `record_count`、`mean_abs_error`、`model_gcs_path`、`trained_at` などの状態 |

モデルは同じユーザーの保存先へ上書きされ、世代管理は実装していません。CLIPモデル本体はプロセス内でキャッシュしますが、画像埋め込みの永続キャッシュはありません。学習と推論で履歴画像の埋め込みをそれぞれ計算します。保存した `clip_id` は現状メタ情報であり、推論時のモデル一致検証には使っていません。

DBの追加定義は [20261024100000_ai_backend_schema.sql](../supabase/migrations/20261024100000_ai_backend_schema.sql)、Edge Functionの設定は [supabase/README.md](../supabase/README.md) を参照してください。

## ローカル実行

Python 3.12を使用するDocker構成に合わせた例です。リポジトリルートから実行します。

```bash
cd mogumap_clip_lgbm
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export AI_BACKEND_API_KEY='dev-only-change-me'
uvicorn api:app --host 127.0.0.1 --port 8000
```

初回の画像処理時にCLIPの重みを取得するため、ネットワーク接続とモデルを置く空き容量が必要です。LinuxではLightGBM用のOpenMPランタイム（Dockerfileでは `libgomp1`）も必要です。起動後は `http://127.0.0.1:8000/docs` でAPI仕様を確認できます。

別ターミナルで、同じ仮想環境を有効にして疎通確認します。

```bash
cd mogumap_clip_lgbm
source .venv/bin/activate
export AI_BACKEND_API_KEY='dev-only-change-me'
curl http://127.0.0.1:8000/health
python generate_demo.py
python test_local.py
python test_api.py
```

`test_local.py` は学習・推論関数を直接呼び、`test_api.py` は起動済みAPIの `/train`・`/predict` を呼ぶ手動確認用スクリプトです。生成データは12ユーザー分の人工評価384件・人工画像48枚で、動作確認用です。実際の料理画像に対する推薦品質を検証するデータではありません。これらの確認にはGemini・Placesの設定は不要です。

### 環境変数

| 変数 | 用途・既定値 |
|---|---|
| `AI_BACKEND_API_KEY` | APIの共有キー。認証付きエンドポイントに必須 |
| `MODEL_BUCKET` | モデル保存先のGCSバケット名。未設定ならローカル保存 |
| `CLIP_DEVICE` | CLIPの実行デバイス。既定値 `cpu` |
| `GOOGLE_CLOUD_PROJECT` | Vertex AIを使うGCPプロジェクト |
| `VERTEX_LOCATION` | Vertex AIの接続先。既定値 `global` |
| `GEMINI_MODEL` | Geminiモデル名。コード上の既定値 `gemini-3.8-flash` |
| `PLACES_API_KEY` | Google Places API (New)のキー |
| `PORT` | Docker起動時の待ち受けポート。既定値 `8080` |

ローカルで `/recommend` まで確認する場合は、追加でVertex AI・Placesの設定とGoogle CloudのApplication Default Credentials（ADC）が必要です。Vertex AIを呼び出す権限、GCSを使う場合は対象バケットへの読み書き権限を用意します。

Edge Function側では `AI_BACKEND_URL` と、バックエンドと同じ `AI_BACKEND_API_KEY` を設定します。`SUPABASE_URL`・`SUPABASE_ANON_KEY` と受信JWTを使って、本人のDB・Storageへアクセスします。

### Docker

このディレクトリでビルドします。

```bash
docker build -t mogumap-ai .
docker run --rm -p 8080:8080 \
  -e AI_BACKEND_API_KEY='dev-only-change-me' \
  mogumap-ai
```

この最小例は学習・推論API用です。`/recommend` とGCS保存には上記環境変数とADCが別途必要です。DockerfileはCLIPの重みをビルド時に取得し、実行時は `HF_HUB_OFFLINE=1`・`TRANSFORMERS_OFFLINE=1` でキャッシュを使います。Uvicornは1ワーカーで起動します。Cloud Runではインスタンスをまたいでモデルを保持するためにGCS保存を使用します。

## ファイル構成

| ファイル | 内容 |
|---|---|
| [api.py](api.py) | FastAPI、入力制約、共有キー認証、各処理の呼び出し |
| [ml.py](ml.py) | CLIP、特徴量作成、個人別LightGBM学習、評価、推論 |
| [recommend.py](recommend.py) | Geminiによる条件抽出、Places検索・写真取得 |
| [storage.py](storage.py) | GCS / ローカルへのモデル保存・読み込み |
| [generate_demo.py](generate_demo.py) | 人工画像・評価データ生成 |
| [test_local.py](test_local.py) / [test_api.py](test_api.py) | ローカル関数 / HTTP APIの動作確認 |
| [requirements.txt](requirements.txt) / [Dockerfile](Dockerfile) | Python依存関係とコンテナ構成 |
=======
# MoguMap AIバックエンド

料理写真と本人の星評価からユーザー別LightGBMモデルを作り、Gemini・Google Placesと組み合わせて実店舗を推薦します。学習は推薦リクエストから分離し、Cloud Run Jobで自動／手動実行します。

## 推薦と学習の条件

| 評価・代表写真が利用できる本人の店舗記録数 | 推薦 |
|---|---|
| 0〜5件 | Geminiの簡易推薦 |
| 6件以上・公開済みモデルあり | LightGBMで本人の星評価を予測 |
| 6件以上・初回学習前／初回学習中／モデル利用不可 | Geminiを継続。モデル障害時は修復学習を予約 |

初回学習は6件から。その後は、最後に成功した学習に含まれない有効店舗が5件以上追加されるごとに、全履歴で再学習します。通常は6・11・16件ですが、初回が8件なら次回13件です。削除との相殺で追加を見落とさないよう、学習済み店舗ID集合で判定します。同じ店舗への再訪問や写真追加は追加店舗数に数えません。再学習中・失敗時は前回成功したモデルを使用します。

iOSの育成タブは登録0件から推薦入力を出すため、0〜5件のGemini推薦はアプリからそのまま使えます。学習操作はアプリには追加しません。

## データの流れ

```mermaid
flowchart TD
    App[iOS] -->|店舗・評価・写真を保存| DB[Supabase DB / Storage]
    DB -->|store / image変更| Dirty[変更ユーザーをDBに記録]
    Scheduler[Cloud Scheduler: 5分ごと] --> Job[Cloud Run Job: training_worker.py]
    Job -->|ジョブ確保・履歴取得| DB
    Job --> Train[CLIP特徴抽出 / LightGBM学習 / 交差検証]
    Train --> GCS[GCS: 世代別モデル]
    GCS --> Publish[DB: 公開モデル世代・学習指標を更新]
    App -->|希望と現在地・JWT| Edge[Supabase ai-recommend]
    Edge -->|本人の履歴・共有キー| API[Cloud Run Service: api.py]
    API --> Places[Geminiで条件抽出 / Placesで実店舗検索]
    Places --> Route{有効件数と公開モデルで分岐}
    Route --> Simple[Gemini: メタ情報から候補を選択]
    Route --> ML[CLIP + 保存済みLightGBM: 星予測]
    Simple --> Result[既存形式で上位3件を返す]
    ML --> Result
    CLI[開発者向けtrain_cli.py] --> Train
```

Edge FunctionはユーザーJWTを検証し、本人の `store` と代表写真を取得します。画像は `record-images` バケットから取得します。バックエンドはSupabaseへ登録された公開モデル世代を自分で確認し、アプリからモデル世代を指定させません。Cloud Run APIの `X-API-Key` 認証と、インスタンス単位のレート制限（既定20回／分）は維持しています。

## 使用モデルと学習方法

| 要素 | モデル・処理 | 学習 |
|---|---|---|
| 写真の特徴抽出 | `sentence-transformers/clip-ViT-B-32`、正規化512次元画像埋め込み | 共有・凍結。追加学習なし |
| 個人の好み予測 | LightGBM `LGBMRegressor` | 本人の1〜5の評価を教師にユーザー別で学習 |
| 条件抽出・簡易推薦 | Vertex AI Gemini、`GEMINI_MODEL` で指定 | 追加学習なし。自由文・カテゴリ別評価の要約・直近の料理の特徴・候補情報から推論 |
| 実店舗検索 | Google Places API (New) Text Search | モデル学習なし |

Geminiは実店舗検索の条件をJSONで抽出し、簡易推薦では検索結果の候補IDと推定評価だけを返します。サーバーが候補ID・重複・評価範囲を検証し、店名はPlacesの結果から復元します。Geminiへの履歴画像送信は行いません。代わりに簡易推薦では、`image.dish_features`（[analyze-dish](../supabase/DISH_ANALYSIS.md) の解析結果、`dish_features_status = 'done'` の写真のみ）の `features` を、新しい順に最大10店ぶん（各店の解析済み写真すべて）、その店の評価・カテゴリと組にして `rated_dishes` として渡します。簡易推薦ではCLIPも候補写真のダウンロードも行いません。

Places検索は現在地を中心とする3,000mの `locationBias` を使用します。厳密な距離制限ではありません。候補は最大10件、返却は最大3件です。カテゴリは抽出したカテゴリを候補に共通で設定し、既訪問店舗の除外はしません。

### LightGBMの入力（通常533次元）

| 特徴量 | 次元 | 内容 |
|---|---:|---|
| 店舗情報 | 3 | Google公開評価、`log(1 + review_count)`、価格帯 |
| カテゴリ | 13 | アプリと共通の13分類のone-hot |
| 本人の履歴 | 5 | 履歴件数、全体平均評価、同カテゴリ平均評価、好き／苦手な写真との類似度 |
| 写真 | 512 | 正規化されたCLIPベクトル |

カテゴリ: 和食／ラーメン・麺類／焼肉・肉料理／中華／カレー／アジア・エスニック／洋食・西洋料理／ファストフード・食堂／カフェ・喫茶／パン／スイーツ／居酒屋・バー／その他。

好きは評価4以上、苦手は2以下の画像を平均し、再正規化したベクトルとのコサイン類似度で表します。本人の評価 `rating` が目的変数で、Google公開評価 `google_rating` は入力です。他ユーザーの履歴は学習しません。

履歴を `rated_at` 順に並べ、各学習行の履歴特徴量はそれより前の記録だけで作ります。現在のアプリ連携では `store.created_at` を `rated_at` とします。日時文字列は時系列順に並ぶ形式へ揃えて入力してください。

LightGBMは決定木を順次追加して誤差を補正する回帰です。履歴件数 `N` に対して次の設定を使います。

```text
n_estimators = min(150, max(20, N * 6))
learning_rate = 0.1
num_leaves = max(2, min(15, N))
max_depth = 4
min_child_samples = 1
min_split_gain = 0
random_state = 42
n_jobs = 1
```

評価は1件抜き交差検証のMAE（平均絶対誤差）です。15件を超える場合は評価対象だけ直近15件に絞り、学習には除外対象以外の全履歴を使います。対象日時より後の記録も学習側に入り得るため、厳密な将来予測の時系列評価ではありません。予測値は1〜5に収め、小数第2位に丸めて降順に返します。

既存iOSの「好みの読み当て」は `round(max(0, 1 - MAE / 4) * 100)` で換算する表示であり、推薦成功確率ではありません。Gemini推薦では架空のMAEを保存しません。

## 履歴とモデルの保存

- 代表写真は `image.created_at` 昇順、同日時は `image.id` 昇順の先頭1枚です。学習と推薦で揃えています。
- 評価・カテゴリ・画像を検証し、重複する店舗IDを除外します。画像は最大5 MiB、読み込めない画像は有効件数から除外します。一時的なStorage通信障害は件数減少として扱わず、再試行／エラーにします。
- 欠損する店舗情報は価格帯2、公開評価3.5、レビュー数50、カテゴリ「その他」で補完します。Places候補のレビュー数既定値は0です。
- 学習対象は最大2,000件。DB履歴はページ取得し、画像取得は最大8並列です。
- 画像の検証結果は内容ハッシュでプロセス内にキャッシュします。CLIP埋め込みの永続キャッシュはありません。
- モデル実体は `gs://<MODEL_BUCKET>/models/{user_id}/{model_version}/model.joblib`。未設定時は `artifacts/models/...`。最終モデル・特徴列名・CLIP ID・学習ポリシー版を保存します。
- `ai_model_status` は最終成功モデルの公開先・件数・MAE・学習済み店舗IDを保持します。失敗時は変更しません。
- DBの実行期限付きロック・ジョブIDによる公開チェックで、古いワーカーの公開を防ぎます。学習中の新しいデータ変更も残します。
- 再試行はユーザーごとに最大5試行。待機時間は指数的に増やします。新しいデータ変更または `--seed-user` で再び処理対象にできます。長時間実行では30秒ごとに5分のリースを更新します。
- 評価・画像の編集は追加5件に数えず、次回学習で反映します。モデルファイルの旧世代は自動削除しません。

## ローカル実行と手動学習

リポジトリルートから実行します。Python 3.12を想定します。

```bash
python3 -m venv mogumap_clip_lgbm/venv
mogumap_clip_lgbm/venv/bin/python -m pip install -r mogumap_clip_lgbm/requirements.txt
mogumap_clip_lgbm/venv/bin/python mogumap_clip_lgbm/generate_demo.py
mogumap_clip_lgbm/venv/bin/python mogumap_clip_lgbm/train_cli.py \
  --records mogumap_clip_lgbm/data/train.json --user-id demo_user_0
```

`generate_demo.py` は既存のデモデータを再生成するため、保持したいデモファイルがある場合は先に退避してください。旧プロトタイプの英語カテゴリは現行の学習対象外です。初回CLIP実行では重み取得が必要です。Linuxでは `libgomp1` などのOpenMPランタイムも必要です。

ルートから `from ml import ...` を実行すると別パッケージを読むことがあるため、上記のようにスクリプトのパスを指定してください。`ModuleNotFoundError: joblib` などの場合は同じPythonで `-m pip install -r ...` を実行します。

実ユーザーの履歴を取得する場合は `SUPABASE_URL` と `SUPABASE_SERVICE_ROLE_KEY` をサーバー側環境に設定します。

```bash
# 読み取りと条件確認だけ。学習もDB更新もしない
mogumap_clip_lgbm/venv/bin/python mogumap_clip_lgbm/train_cli.py \
  --source supabase --user-id <UUID> --dry-run

# 新規5件の条件を省略してテスト。最低6件は必須。本番モデル・統計を更新しない
mogumap_clip_lgbm/venv/bin/python mogumap_clip_lgbm/train_cli.py \
  --source supabase --user-id <UUID> --force

# 明示的に本番モデルを公開する運用。自動学習と同じDB排他・公開手順を使う
mogumap_clip_lgbm/venv/bin/python mogumap_clip_lgbm/train_cli.py \
  --source supabase --user-id <UUID> --force --publish
```

既定の手動出力先はこのディレクトリの `artifacts/manual/`。`--gcs-test` を付けるとGCSの `manual-tests/` 以下に保存し、DB・本番モデルは更新しません。CLIは学習件数、CLIP時間、学習・評価時間、全体時間、MAE、ファイル容量、保存先を表示します。

APIのローカル起動:

```bash
export AI_BACKEND_API_KEY='dev-only-change-me'
mogumap_clip_lgbm/venv/bin/python -m uvicorn api:app \
  --app-dir mogumap_clip_lgbm --host 127.0.0.1 --port 8000
```

### API

| パス | 内容 |
|---|---|
| `GET /health` | 死活監視。外部サービスやモデルは確認しない |
| `POST /recommend` | `user_id`, `free_text`, `lat`, `lng`, `history`。学習しない |
| `POST /train` | 開発者向け。`user_id`, `records`（最低6件）。世代別保存するがDBへ公開しない |
| `POST /predict` | 開発者向け。`user_id`, `model_version`, `history`, `candidates`。既存モデルで推論 |

`/health` 以外は `X-API-Key` が必須です。バックエンドはユーザーJWTを直接検証しないため、ユーザー向けアクセスは認証済みEdge Function経由にします。

学習履歴の必須情報は `user_id`, `place_id`, `image_id`, `category`, `price_level`, `google_rating`, `review_count`, `rating`, `rated_at` と `image_base64` または `image_path`。画像パスはこのディレクトリを基準とし、Base64があれば優先します。候補には本人の評価・ユーザーID・日時は不要です。

`/recommend` の応答例:

```json
{
  "predictions": [{"place_id":"real-place-id","name":"サンプル食堂","category":"和食","predicted_rating":4.2}],
  "conditions": {"category":"和食","keywords":[],"search_query":"和食"},
  "mode": "gemini"
}
```

`mode` は `gemini` または `lightgbm`。既存iOSは `predictions` のフィールドを引き続き読み取れます。Edge FunctionはFastAPIのエラーを既存の `{"error":"..."}` 形式に変換します。

## GCPでの自動実行

Cloud SchedulerからCloud Run Jobを起動します。[GCP公式手順](https://docs.cloud.google.com/run/docs/execute/jobs-on-schedule)に従い、Job起動APIにはOAuth認証を使います。推薦用Cloud Run Serviceへのユーザー操作とは独立です。

1. `supabase/migrations/20261025120000_ai_background_training.sql` を適用する。store/imageトリガー・ジョブ・公開処理を追加し、既存ユーザーも初回確認対象に登録します。
2. 既存GCPプロジェクトにログインし、下記環境変数を設定する。
3. Secret Managerに既存共有キー・Placesキー・Supabaseサーバーキーを用意する。値をスクリプトに直書きしない。
4. `setup_gcp.sh`、`deploy_gcp.sh` を実行する。
5. `supabase functions deploy ai-recommend` でEdge Functionを更新する。
6. 手動Jobで条件確認・学習テスト後、自動Jobを1回実行しDBの公開世代と推薦方式を確認する。
7. `enable_schedule.sh` で5分ごとの自動起動を有効にする。

```bash
export PROJECT_ID='<既存GCPプロジェクト>'
export REGION='asia-northeast1'
export MODEL_BUCKET='<既存モデルバケット名>'
export SUPABASE_URL='https://<project>.supabase.co'
export API_SERVICE='<既存Cloud Runサービス名>'
export IMAGE_TAG='<一意のリリースタグ>'

bash mogumap_clip_lgbm/deploy/setup_gcp.sh
bash mogumap_clip_lgbm/deploy/deploy_gcp.sh

export TRAIN_USER_ID='<テスト対象ユーザーUUID>'
bash mogumap_clip_lgbm/deploy/run_manual.sh --dry-run
bash mogumap_clip_lgbm/deploy/run_manual.sh --test
gcloud run jobs execute mogumap-train --region="$REGION" --project="$PROJECT_ID" --wait
bash mogumap_clip_lgbm/deploy/enable_schedule.sh
```

スクリプトの既定Secret名は `supabase-service-role-key`、`ai-backend-api-key`、`places-api-key`。既存名に合わせて `SUPABASE_KEY_SECRET`・`AI_KEY_SECRET`・`PLACES_KEY_SECRET` を上書きできます。Job名などの上書き変数は各スクリプト冒頭を参照してください。

学習Jobは初期値2 CPU・4 GiB、1タスク、最大10ユーザー、次のユーザーへ進む時間予算600秒、タスク全体上限1,800秒です。1ユーザーの学習が時間予算を超える場合もタスク上限までは処理します。実データ量に合わせて調整してください。スケジュールはデプロイ時に停止状態にし、検証後に明示的に再開します。

`ai_training_jobs` の `state`・`error_code`、`ai_training_dirty_users` の `attempts`・`lease_until` を運用で確認してください。最大5試行に達したユーザー、古いリース、Geminiへの退避、学習が長時間成功していないユーザーを監視対象にします。例外ログにはキーや画像を含めず、エラーの型を記録します。

再試行対象の再登録は `training_worker.py --seed-user <UUID>`。切り戻し時はSchedulerをpauseし、正常な前世代モデルの `ai_model_status`（モデル世代・パス・学習済み集合・件数・MAEを一組で）をサーバー権限で復元します。同期学習を含む旧APIへ戻さず、学習分離後の安定リビジョンを使ってください。

### 環境変数

| 変数 | 用途 |
|---|---|
| `AI_BACKEND_API_KEY` | Edge→推薦APIの共有キー |
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | APIの公開モデル確認、Job／CLIのデータ取得・ジョブ操作。サーバーのみ |
| `MODEL_BUCKET` | GCSバケット名。未設定ならローカル保存 |
| `CLIP_DEVICE` | 既定 `cpu` |
| `GOOGLE_CLOUD_PROJECT` | Vertex AIのプロジェクト |
| `VERTEX_LOCATION`, `GEMINI_MODEL` | 既定 `global`, `gemini-3.8-flash`。利用可能なモデルに合わせて変更 |
| `PLACES_API_KEY` | Places API (New) |
| `RATE_LIMIT_PER_MINUTE` | インスタンス単位のAPI制限。既定20 |
| `TRAIN_USER_ID` | 手動検証JobでCLI引数の代わりに使うユーザーUUID |

GCPではサービスアカウントのADCを使用します。DockerfileはCLIPをビルド時に取得し、実行時は `HF_HUB_OFFLINE=1`・`TRANSFORMERS_OFFLINE=1` でネットワーク確認を避けます。

## 処理時間とファイル容量

**実測と概算を区別してください。** この変更のローカル確認では、人工データ6件・CPU・`OMP_NUM_THREADS=2`・CLIP初回ロードを含め、CLIP処理11.734秒、特徴量作成＋学習＋交差検証0.225秒、全体11.965秒、保存ファイル59,272 bytesでした。CLIP重みはローカルキャッシュを使用し、GCSやGemini等の通信は含みません。単回の動作確認であり、Cloud Runの性能保証や実画像での推薦品質評価ではありません。

性能設計前の仮置きとして、ウォームCPUで画像1枚のCLIP処理を50〜300ms、LightGBMの1店舗予測を1〜10ms程度とすると、写真からの推論計算は1店舗約0.05〜0.3秒が目安です。これらの値は推論の実測値ではありません。モデル取得・履歴特徴量作成・通信・コールドスタートは別途かかります。

現在のML推論は候補だけでなく履歴画像も再計算します。履歴 `N`、候補 `K`、画像特徴抽出 `E` とすると、概ね `T_predict = モデル取得 + E(N+K) + 特徴量作成 + LightGBM予測`。例えば履歴30件＋候補10件は40枚が対象です。Gemini経路はCLIP処理を行いません。

学習は `E(N)` に加え、最終学習1回と交差検証最大15回。5回ごとの追加件数ではなく、毎回の全履歴サイズが処理時間を決めます。モデルは最大150本・各15葉以下の決定木とメタ情報で、ユーザー別容量予算として数十KiB〜1MiBを仮置きできます。CLIP本体・画像・旧世代は含めません。CLIの `model_size_bytes` と各時間で実データの計測を更新してください。

## テスト

```bash
cd mogumap_clip_lgbm
venv/bin/python -m pip install -r requirements-dev.txt
venv/bin/python -m unittest discover -s tests -v
cd ..
node --disable-warning=ExperimentalWarning supabase/tests/ai_recommend_test.mjs
bash supabase/tests/check_ai_training_db.sh
```

Pythonテストは外部APIをモックし、実際のLightGBM学習・シリアライズも検証します。DBテストは一時PostgreSQLコンテナで、マイグレーション、画像後着、排他、期限切れ、公開・失敗・権限を確認し、既存DBへ接続しません。Docker実行権限が必要です。Node 24によるEdge Functionテストも外部通信をモックして実コードを実行します（Denoの型チェックは別途必要です）。

主な実装は `policy.py`（条件）、`history.py`（検証）、`repository.py`（Supabase）、`training_worker.py`（自動学習）、`train_cli.py`（手動）、`api.py`（API）、`recommend.py`（候補・Gemini）、`ml.py`（CLIP・LightGBM）、`storage.py`（世代別保存）です。変更方針は [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) を参照してください。
>>>>>>> origin/main
