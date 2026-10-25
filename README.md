# もぐマップ — 写真を撮るだけで、友達と共有できる自分だけのグルメマップ

[![IMAGE ALT TEXT HERE](https://jphacks.com/wp-content/uploads/2026/07/IMG_5316.png)](https://www.youtube.com/watch?v=piaNsc6ilBI)

## 製品概要

写真を撮るだけでお店のレビューを記録でき、味の感覚が近い友達と共有できる iOS アプリです。
記録がたまるほど、自分の好みを学習した AI がお店をおすすめしてくれます。

## 背景

**「Google レビューや食べログを見ても、自分好みのお店がなかなか見つからない」**。
これが、私たちがもぐマップで解決したい課題です。

口コミサイトの評価は、不特定多数の平均点です。
味の濃さ、量、雰囲気、値段の感じ方は人によって違うので、平均点の高いお店が自分に合うとは限りません。

## 解決策: 2つの軸

この課題に対して、もぐマップは「平均点」の代わりに、**自分に合うものさし**でお店を選べるようにします。そのための軸が2つあります。

```
          課題: 口コミサイトでは、自分好みのお店が見つからない
                                │
            ┌───────────────────┴───────────────────┐
            ▼                                       ▼
  機能1: フレンドのおすすめ               機能2: 自分に特化した AI
  味の感覚・金銭感覚が近い                自分の評価から好みを学習し、
  友達の「良い！」で選ぶ                  気分に合うお店を予測する
            ▲                                       ▲
            └───────────────────┬───────────────────┘
                                │
          土台: 写真を撮るだけで、お店のレビューを記録できる
```

### 機能1: フレンドのおすすめ — 味の感覚が近い友達の「良い！」で選ぶ
私たちは、**本当に信頼できるお店**とは、味の感覚や金銭感覚が近い**友達が「良い！」とおすすめしたお店**だと考えています。
もぐマップでは、実際に行ったお店のレビューを友達と共有し、マップとタイムラインで友達のおすすめを見ながらお店を選べます。

### 機能2: 自分に特化した AI — 自分の好みを学習してお店を提案する
友達がまだ行っていないお店は、友達のおすすめでは選べません。
そこで、過去の来店履歴とレビューの評価から好みを学習した**自分専用の AI モデル**を育て、行きたい気分に合うお店を、自分が付けそうな★の予測とともに提案します。

### 土台: 写真を撮るだけのレビュー登録
2つの機能は、どちらも**記録がたまること**が前提です。友達と共有する情報も、AI の学習データも、記録から生まれます。
ところが、**レビューを書くのはめんどくさい**ものです。お店の名前を調べて、場所を登録して、カテゴリを選んで……という手間があると、記録は続きません。

だから私たちが最も大切にしたのは、**お店のレビュー登録の手軽さ**です。
もぐマップでは、**料理の写真を撮るだけで、お店の名前・場所・カテゴリ（ラーメンなのか、寿司なのか）が自動で登録されます**。
ユーザーが入力するのは、**5段階の評価**と、任意の**コメント**だけです。

1. **撮る**: お店で料理の写真を撮る（またはライブラリから選ぶ）
2. **選ぶ**: 写真の撮影位置から近くのお店が自動で選ばれる（違えば候補から選び直す）
3. **評価する**: ★を付けて保存する。コメントは任意

## 製品説明

アプリは5つのタブで構成されています。

| タブ | できること |
|---|---|
| 登録 | 写真を撮る → 近くのお店が自動で選ばれる → ★評価とコメントを付けて保存 |
| マップ | 自分と友達が記録したお店を、写真入りのピンで地図に表示 |
| タイムライン | 友達が直近3日間に行ったお店が、新しい順に流れてくる |
| 育てる | 記録数に応じてキャラクターが成長。気分を入力すると、AI が好みに合うお店を3軒おすすめ |
| プロフィール | 自分の記録・統計、プロフィール編集、フレンドの管理 |

## 特長

### 土台: 写真を撮るだけで、お店が自動で登録される

#### 撮影位置からお店を特定
写真の EXIF（撮影情報）から GPS の緯度・経度を読み取り、近くの飲食店を Google Places API の Nearby Search で探します。

- 検索条件: 半径 **1km**、種類は `restaurant` / `cafe`、**距離順**に最大 **5件**
- **一番近いお店を最初から選んだ状態**で表示します。違っていれば、距離（m）付きの候補一覧から選び直せます。
- 写真が複数あるときは、並び順で最初に位置情報を持つ写真（表紙を優先）の撮影位置を使います。
- 位置情報のない写真（アプリ内カメラで撮った写真など）では、**現在地**で検索します（取得のタイムアウトは15秒）。
- 撮影日時も EXIF の `DateTimeOriginal` から読み取ります。タイムゾーン情報（`OffsetTimeOriginal`）があれば考慮します。

#### カテゴリを13分類に自動で振り分け
Google Places が返すお店の種別（`primaryType` / `types`）から、アプリ独自の**13カテゴリ**に自動で分類します。

和食／ラーメン・麺類／焼肉・肉料理／中華／カレー／アジア・エスニック／洋食・西洋料理／ファストフード・食堂／カフェ・喫茶／パン／スイーツ／居酒屋・バー／その他

1. `primaryType` が具体的な種別（例: `ramen_restaurant`）なら、その分類を使う
2. `primaryType` が汎用的な種別（例: `restaurant`）なら、`types` の中から最初に当てはまる分類を探す
3. どれにも当てはまらなければ「その他」

#### 再訪問は自動でまとめる
同じお店（同じ Google のお店 ID）をもう一度記録すると、新しい記録は作らず、**訪問回数（リピート回数）を +1** して既存の記録に写真を追加します。
登録画面にも「記録済みのお店です。N回目の訪問として保存します」と表示されます。

#### 入力は★評価とコメントだけ
- 必須: 写真1枚以上、お店、カテゴリ（自動で入る）、★評価（1〜5）
- 任意: コメント
- 写真は1件につき最大 **10枚**。取り込み時に長辺 **2048px** に縮小し、アップロード時は JPEG 品質 **0.8** で圧縮します。
- 写真のアップロードに一部失敗しても、記録自体は保存されます。「写真を再送する」か「写真なしで完了する」を選べます。

### 機能1: フレンドのおすすめ — 味の感覚が近い友達の「良い！」がわかる

#### フレンド申請と承認
- 各ユーザーには、英小文字・数字・`_` の **3〜20文字**の**ユーザー名**があります。初回登録時に10桁のランダムなユーザー名が自動で付き、プロフィール編集で変更できます。
- ユーザー名の**完全一致**で検索し、フレンド申請を送ります。相手が承認すると、お互いの記録が見えるようになります。
- 相手からすでに申請が来ている人に申請すると、その場でフレンドが成立します。
- 届いた申請の件数は、プロフィールタブのバッジに表示されます（アプリ起動時・復帰時に更新）。

#### マップで友達のお店を見る
Google Maps SDK for iOS の地図上に、自分と友達が記録したお店をピンで表示します。

- ピンは **56pt の角丸の写真**です。そのお店の1枚目の写真を表示し、写真がなければカテゴリの色とアイコンを表示します。
- **白い枠が自分**、**カテゴリ色の枠がフレンド**の記録です。
- 自分と友達の**両方が記録したお店**には、人のアイコンのバッジが付きます。
- 「自分／フレンド／両方」と、カテゴリ（13分類）で絞り込めます。
- ピンをタップすると、店名・カテゴリ・★評価・リピート回数・写真のカードが出ます。

#### タイムラインで友達の最新の記録を見る
- 友達（と自分）が**直近3日間**に記録したお店を、日付ごとに新しい順で表示します。
- 「すべて／自分／フレンド」で絞り込めます。時刻は「たった今」「N分前」「昨日 19:42」のように表示します。
- 友達がまだいないときは、フレンド探しに誘導します。

#### 公開範囲はデータベースで守る
「誰に見せるか」は、アプリのコードではなく、データベースの行単位のアクセス制御（**RLS**: Row Level Security）で制御しています。
フレンドでない人の記録や写真は、データベースから取り出すこと自体ができません。

### 機能2: 自分に特化した AI — 記録するほど、自分専用の AI が育つ

#### キャラクターの成長
登録したお店の数（= AI の学習データ数）に応じて、キャラクターが3段階で成長します。

| レベル | 名前 | 必要な記録数 | できること |
|---|---|---|---|
| Lv.1 | ごはんつぶ | 0〜4件 | 「あとN件で Lv.2」と表示 |
| Lv.2 | みならいコック | 5件〜 | AI のおすすめが使える |
| Lv.3 | まんぷく先生 | 20件〜 | 最大レベル |

キャラクターはレベルごとのコマ画像を **8fps** でコマ送りして動きます（iOS の「視差効果を減らす」設定がオンなら静止画）。

#### 気分からのおすすめ
「渋谷で静かなデート向けの和食」のような自由な言葉を入力すると、次の流れでおすすめを3軒出します。

1. **Gemini** で、入力を検索条件（カテゴリ・キーワード・検索文）に変換する。**店名は絶対に作らせない**
2. 検索条件と現在地で **Google Places Text Search** を呼び、実在するお店を最大 **10件**取得する（現在地から半径 3km を優先）
3. 自分専用の AI モデルで、それぞれのお店に自分が付けそうな★を予測する
4. 予測★の高い **上位3件**を表示する。「Google Mapsで見る」でそのお店を開ける

#### AI の精度の見える化
AI がどれくらい自分の好みを当てられるかを、「好みの読み当て」として表示します。

- 精度は **LOOCV**（記録を1件ずつ抜いて残りで学習し、抜いた1件の★を予測する検証方法）で測った**平均絶対誤差（MAE）**です。
- 表示は「**読み当て率 = (1 − MAE / 4) × 100 %**」と「**5段階で±0.xのズレ**」です。

## 解決できること

- **口コミサイトでは見つからない、自分好みのお店に出会える**: 平均点ではなく、味の感覚が近い友達の評価（機能1）や、自分の好みを学習した AI（機能2）をもとにお店を選べます。
- **レビューが続かない問題を解消する**: 入力は★評価とコメントだけなので、食事のたびに気軽に記録できます。
- **行ったお店を忘れない**: 「あのおいしかったお店どこだっけ」を、写真入りの地図ですぐに振り返れます。

## 今後の展望

- **食の好みでつながる「食のマッチング」**: もぐマップには、ユーザー一人ひとりの食の好みに特化した AI モデルと、料理写真から抽出した見た目の特徴がたまっていきます。これを使って、まだ友達ではない人の中から**味の感覚や金銭感覚が近い人**を見つけ、つなげることを目指しています。「信頼できるのは、好みが近い人のおすすめ」という考えを、友達の外にも広げます。
- **友達と行くお店を、2人の好みから提案する**: それぞれの AI モデルの予測を組み合わせ、2人ともが満足しそうなお店を提案します。
- **学習開始の条件を見直す**: 現在は記録5件から学習を始めていますが、精度を上げるため、**写真が20枚程度たまってから**学習を始める方針です（Lv.3 の到達条件と同じ20件）。
- **料理写真の特徴から好みの傾向を出す**: 写真から抽出して保存している特徴（スープの濁り・背脂の量・盛り付けなど）をユーザーごとに集計し、「こってり派」「トッピング多め派」といった好みの傾向を表示します。
- **AI のレベルが上がった後の楽しみ**: Lv.3 到達後も記録を続けたくなる仕組みを追加します。

## 注力したこと

### 1. レビュー登録の手軽さ
写真から店名・場所・カテゴリを自動で埋め、入力を★評価とコメントだけにしました。
一番近いお店を最初から選んだ状態にし、再訪問も自動でまとめるので、多くの場合は★を付けて保存ボタンを押すだけです。
- [RecordCreateViewModel.swift](GourmetShareMap/Features/Record/ViewModels/RecordCreateViewModel.swift)
- [PhotoLocationReader.swift](GourmetShareMap/Services/PhotoLocationReader.swift)
- [FindNearestShop.swift](GourmetShareMap/Services/Places/FindNearestShop.swift)
- [PlaceCategoryClassifier.swift](GourmetShareMap/Services/Places/PlaceCategoryClassifier.swift)
- [RecordStore.swift](GourmetShareMap/Core/RecordStore.swift)

### 2. AI に店名を作らせない
生成 AI にお店を直接答えさせると、存在しないお店を作ってしまうことがあります。
そこで Gemini には「検索条件への変換」だけを任せ、実際のお店は Google Places から取得する2段構成にしました。
- [mogumap_clip_lgbm/recommend.py](mogumap_clip_lgbm/recommend.py)

### 3. 少ないデータでも育つ AI
1人あたりの記録は5〜数十件と少ないため、大きなモデルをユーザーごとに学習することはできません。
そこで、写真の特徴抽出（CLIP）は学習済みのモデルを全員で共有し、ユーザーごとには軽い回帰モデル（LightGBM）だけを学習する構成にしました。
評価も、データが少なくても安定する LOOCV を採用しています。
- [mogumap_clip_lgbm/ml.py](mogumap_clip_lgbm/ml.py)
- [mogumap_clip_lgbm/REQUIREMENTS.md](mogumap_clip_lgbm/REQUIREMENTS.md)（要件定義）

### 4. 料理写真の見た目を、集計できるデータにする
「好み」を写真の見た目からも捉えるため、料理写真の特徴を Gemini で抽出し、JSON で保存しています。
自由な文章ではなく、カテゴリごとに定義した選択肢と段階評価だけで答えさせるので、ユーザー単位で集計できます。
- [supabase/functions/analyze-dish/](supabase/functions/analyze-dish/)
- [supabase/DISH_ANALYSIS.md](supabase/DISH_ANALYSIS.md)

### 5. API キーと個人のデータを守る
- AI バックエンドや Gemini のキーはアプリに埋め込まず、Supabase Edge Function を経由して呼び出します。
- 記録・写真・プロフィール画像の公開範囲は、すべて RLS と Storage のポリシーで制御しています。
- [supabase/migrations/](supabase/migrations/)
- [supabase/functions/ai-recommend/index.ts](supabase/functions/ai-recommend/index.ts)

## 開発技術

### 技術スタック

| 分類 | 技術 |
|---|---|
| iOS アプリ | Swift / SwiftUI、Observation、AuthenticationServices（Sign in with Apple）、Core Location、AVFoundation、PhotosUI、ImageIO |
| Swift Package | supabase-swift 2.55.4、ios-maps-sdk 11.2.0 |
| 地図・お店 | Google Maps Platform（Maps SDK for iOS、Places API (New): Nearby Search / Text Search / Place Details） |
| バックエンド | Supabase（Auth / PostgreSQL / Storage / Edge Functions / Database Webhooks） |
| AI バックエンド | Python 3.12、FastAPI、uvicorn、sentence-transformers（CLIP `clip-ViT-B-32`）、LightGBM、google-genai |
| 生成 AI | Gemini API（Vertex AI `gemini-3.8-flash`: おすすめの検索条件、`gemini-3.1-flash-lite`: 料理写真の特徴抽出） |
| インフラ | Google Cloud Run、Cloud Storage、Supabase Edge Functions（Deno / TypeScript） |
| デバイス | iPhone（iOS 26.5 以降） |

### システム構成

```
[iPhone アプリ（Swift / SwiftUI）]
   │
   ├─ Sign in with Apple ───────────────▶ Supabase Auth
   │
   ├─ 記録・写真・フレンド ─────────────▶ Supabase PostgreSQL / Storage（RLS で公開範囲を制御）
   │                                          │
   │                                          └─ 写真の保存（image INSERT）
   │                                               └─▶ Database Webhook
   │                                                    └─▶ Edge Function: analyze-dish
   │                                                         └─▶ Gemini（料理の特徴を JSON で保存）
   │
   ├─ 地図表示・お店の候補検索 ─────────▶ Google Maps SDK / Google Places API
   │
   └─ AI おすすめ ─▶ Edge Function: ai-recommend（ユーザーの記録と写真を集める）
                       └─▶ Cloud Run: FastAPI（CLIP + LightGBM）
                              ├─▶ Vertex AI Gemini（気分 → 検索条件）
                              ├─▶ Google Places Text Search（候補のお店）
                              └─▶ Cloud Storage（ユーザーごとのモデル）
```

## 独自技術

### 1. 写真からのお店の自動特定
写真の EXIF から GPS 座標を読み取ります。南緯・西経（Ref が `S` / `W`）は符号を反転し、`(0, 0)` などの不正な座標は位置なしとして扱います。
その座標で Places API の Nearby Search を呼び、距離順の先頭を自動で選びます。

```json
// POST https://places.googleapis.com/v1/places:searchNearby
// X-Goog-FieldMask: places.id,places.displayName,places.location,places.primaryType,places.types
{
  "languageCode": "ja",
  "includedTypes": ["restaurant", "cafe"],
  "maxResultCount": 5,
  "rankPreference": "DISTANCE",
  "locationRestriction": { "circle": { "center": { "latitude": 35.71, "longitude": 139.76 }, "radius": 1000.0 } }
}
```

新しいお店では Place Details（`rating` / `priceLevel` / `userRatingCount`）も取得し、AI の学習用に保存します。
価格帯は `INEXPENSIVE` → 1、`MODERATE` → 2、`EXPENSIVE` → 3、`VERY_EXPENSIVE` → 4 に変換します。
- [PhotoLocationReader.swift](GourmetShareMap/Services/PhotoLocationReader.swift)
- [FindNearestShop.swift](GourmetShareMap/Services/Places/FindNearestShop.swift)
- [FindPlaceDetails.swift](GourmetShareMap/Services/Places/FindPlaceDetails.swift)

### 2. 13カテゴリへの自動分類
分類のルールは、優先順位つきの配列で持っています。

```swift
static func category(primaryType: String?, types: [String]) -> String {
    // 主カテゴリが具体的なら優先する。汎用のrestaurant等は詳細typesで補完する。
    let specificRules = categoryRules.dropLast()
    if let primaryType,
       let rule = specificRules.first(where: { $0.types.contains(primaryType) }) {
        return rule.name
    }
    let typeSet = Set(types)
    return specificRules.first(where: { !$0.types.isDisjoint(with: typeSet) })?.name ?? "その他"
}
```
- [PlaceCategoryClassifier.swift](GourmetShareMap/Services/Places/PlaceCategoryClassifier.swift)

### 3. 写真入りのマップピン
SwiftUI で作ったピン（`ShopPinView`）を `ImageRenderer` で画像にし、Google Maps のマーカーに使っています。

- 見た目の組み合わせ（写真・カテゴリ・自分かフレンドか・選択中か）ごとにピン画像をキャッシュし、変わったマーカーだけを更新します。
- 写真は1枚目を署名付き URL で取得し、**168px**（56pt の3倍）に縮小して使います。並列に取得し、写真のないお店は再取得しません。
- 自分と友達の両方が記録したお店は、`google_place_id` の積集合で判定してバッジを付けます。
- [GoogleMapView.swift](GourmetShareMap/Features/Map/Views/GoogleMapView.swift)
- [ShopPinView.swift](GourmetShareMap/Features/Map/Components/ShopPinView.swift)
- [StorePhotoLoader.swift](GourmetShareMap/Features/Map/ViewModels/StorePhotoLoader.swift)
- [MapViewModel.swift](GourmetShareMap/Features/Map/ViewModels/MapViewModel.swift)

### 4. ユーザーごとの個別 AI モデル
1件の記録を、次の特徴量に変換して LightGBM で★を予測します。

| 特徴量 | 内容 |
|---|---|
| `google_rating`、`review_count_log`、`price_level` | Google の評価、レビュー数（log1p）、価格帯 |
| `cat_0` 〜 `cat_12` | 13カテゴリの one-hot |
| `hist_count`、`hist_avg`、`cat_hist_avg` | その時点までの評価件数、平均★、同じカテゴリの平均★ |
| `liked_image_similarity` | ★4以上を付けた写真の平均ベクトルとのコサイン類似度 |
| `disliked_image_similarity` | ★2以下を付けた写真の平均ベクトルとのコサイン類似度 |
| `clip_000` 〜 | 料理写真の CLIP 埋め込み |

- 学習データは記録を時系列に並べ、**各記録より前の評価だけ**を履歴として特徴量を作ります（未来の情報を使わない）。
- CLIP（`sentence-transformers/clip-ViT-B-32`）は学習せず、全ユーザーで共有します。重みは Docker イメージに含め、オフラインで動かします。
- LightGBM のハイパーパラメータは、データ数 `n` に応じて調整しています。

```python
LGBMRegressor(
    n_estimators=min(150, max(20, 6 * n)),
    learning_rate=0.1,
    num_leaves=max(2, min(15, n)),
    max_depth=4,
    min_child_samples=1,
    min_split_gain=0,
    random_state=42,
)
```
- 精度は直近 **15件**までの LOOCV で測り、予測値を 1〜5 に収めてから MAE を計算します。
- モデルは Cloud Storage の `models/{user_id}/model.joblib` に保存します。
- [mogumap_clip_lgbm/ml.py](mogumap_clip_lgbm/ml.py)
- [mogumap_clip_lgbm/storage.py](mogumap_clip_lgbm/storage.py)

### 5. 気分からのおすすめ（幻覚を防ぐ2段構成）
Gemini には、JSON Schema で形を決めた検索条件だけを答えさせます。

| 項目 | 内容 |
|---|---|
| `category` | 13カテゴリ＋「指定なし」から1つ |
| `keywords` | キーワードの配列 |
| `search_query` | Places Text Search に渡す検索文 |

プロンプトでは「店名は絶対に創作しない」と指示しています。
その検索文で Places Text Search（最大10件、現在地から半径 3km を優先、写真付き）を呼び、各候補を個人モデルで予測して上位3件を返します。
- [mogumap_clip_lgbm/recommend.py](mogumap_clip_lgbm/recommend.py)
- [mogumap_clip_lgbm/api.py](mogumap_clip_lgbm/api.py)
- [supabase/functions/ai-recommend/index.ts](supabase/functions/ai-recommend/index.ts)

### 6. 料理写真の特徴の自動抽出
写真が保存されると、Database Webhook で Edge Function `analyze-dish` が起動し、Gemini で料理の見た目の特徴を抽出して `dish_analysis` テーブルに JSON で保存します。
アプリ側のコードは変更せず、裏で自動的に動きます。

- **カテゴリはユーザーが選んだ値**をそのまま使い、カテゴリごとに定義した部品表に沿って記述させます。たとえばラーメンなら次の項目です。
  - スープ（系統・濁り1〜5・色の濃さ1〜5・粘度）、タレ、油（種類・量0〜4・背脂の粒）、振りもの
  - 麺（太さ・形・色・量）、チャーシュー（種類・厚さ・枚数・面積）、卵、メンマ、ネギ、その他の具
  - 器（素材・テイスト・形）、盛り付けスタイル、色の印象 など
- 値は**選択肢と段階評価に限定**し、JSON Schema で型を固定しています。写っていないものは推測させず `null` にします。
- 13カテゴリ（和食は形式ごとに5表）すべてに部品表を定義しています。
- 1枚あたりの処理時間を計測し、数分かかった `gemini-3.8-flash` から、数秒で終わる `gemini-3.1-flash-lite` に切り替えました（実測 7.4秒 / 4.8秒）。

```json
{
  "category": "ラーメン・麺類",
  "format": "汁あり",
  "lineage": "背脂醤油",
  "parts": {
    "soup": { "base": "醤油", "turbidity": 3, "color_depth": 3, "viscosity": "さらさら" },
    "oil": { "types": ["背脂粒"], "amount": 3, "fat_grain": "粗い" },
    "chashu": { "type": "煮豚", "thickness": "中", "count": 3, "area_ratio": 0.5 },
    "menma": { "shape": "太切り" },
    "negi": { "type": "青ネギ小口" }
  },
  "common": {
    "overall": { "volume": 3, "plating": "素朴", "color_impression": "茶系中心" },
    "vessel": { "material": "磁器", "style": "和（染付・土物）", "shape": "丼" }
  },
  "caption": "波模様の青い丼に盛られた背脂醤油ラーメン。"
}
```
- [supabase/functions/analyze-dish/index.ts](supabase/functions/analyze-dish/index.ts)（Webhook の受付 → 解析 → 保存）
- [supabase/functions/analyze-dish/vocab/v1.ts](supabase/functions/analyze-dish/vocab/v1.ts)（13カテゴリの部品表）
- [supabase/functions/analyze-dish/schema.ts](supabase/functions/analyze-dish/schema.ts)（プロンプトと JSON Schema の組み立て）
- [supabase/DISH_ANALYSIS.md](supabase/DISH_ANALYSIS.md)（設計と保存形式）

### 7. フレンド申請をデータベースで完結させる
申請・承認は、Postgres の関数（RPC）としてデータベース側に実装しています。

| 関数 | 動き |
|---|---|
| `send_friend_request(p_addressee_id)` | 申請を作る。相手からすでに申請が来ていれば、その場でフレンドを成立させる |
| `accept_friend_request(p_requester_id)` | 自分宛ての申請だけを承認し、双方向のフォローを作る |
| `search_user_by_user_name(p_user_name)` | ユーザー名の完全一致で検索し、自分との関係（本人・フレンド・申請中・申請受信・なし）も返す |

- 同じ2人の処理が同時に走っても壊れないよう、`pg_advisory_xact_lock` で直列化しています。
- アプリから `friend` テーブルに直接書き込むことはできず、必ずこの関数を通ります。
- [supabase/migrations/20261024150100_friend_request.sql](supabase/migrations/20261024150100_friend_request.sql)
- [supabase/migrations/20261024150200_friend_search.sql](supabase/migrations/20261024150200_friend_search.sql)
- [FriendRepository.swift](GourmetShareMap/Repositories/FriendRepository.swift)

## API

### AI バックエンド（Cloud Run / FastAPI）
認証は `X-API-Key` ヘッダーです。アプリからは直接呼ばず、Edge Function `ai-recommend` を経由します。

| メソッド | パス | リクエスト | レスポンス |
|---|---|---|---|
| GET | `/health` | なし | `{ "status": "ok" }` |
| POST | `/train` | `user_id`、`records`（5〜2000件） | 学習結果（同じユーザーの学習中は 409） |
| POST | `/predict` | `user_id`、`history`（〜2000件）、`candidates`（1〜100件） | `{ "predictions": [...] }`（モデルがなければ 409） |
| POST | `/recommend` | `user_id`、`free_text`（1〜500字）、`lat`、`lng`、`history` | `{ "predictions": [上位3件], "conditions": {...}, "model_stats": {...} }` |

`/recommend` は、毎回最新の記録で学習し直してから予測します。

### Supabase Edge Functions

| 関数 | 呼び出し元 | 役割 |
|---|---|---|
| `ai-recommend` | iOS（ユーザーのアクセストークン付き） | 評価済みの記録と写真を集めて AI バックエンドに転送し、精度を `ai_model_status` に保存する |
| `analyze-dish` | Database Webhook（`image` の INSERT） | 料理写真を Gemini で解析し、`dish_analysis` に保存する |

## データベース構成

| テーブル | 主な列 | 説明 |
|---|---|---|
| `user` | `id`、`user_name`、`name`、`email`、`bio`、`profile_image` | ユーザー。`user_name` は3〜20文字で一意 |
| `store` | `user_id`、`name`、`category`、`reputation`、`google_place_id`、`latitude`、`longitude`、`memo`、`repeat_num`、`google_rating`、`price_level`、`review_count` | お店の記録（ユーザーごと） |
| `image` | `store_id`、`image` | 記録の写真（Storage 内のパス） |
| `friend` | `user_id`、`friend_id` | フォロー関係（相互フレンドは2行） |
| `friend_request` | `requester_id`、`addressee_id` | 承認待ちの申請 |
| `ai_model_status` | `user_id`、`record_count`、`mean_abs_error`、`model_gcs_path`、`trained_at` | AI の学習状況と精度 |
| `dish_analysis` | `image_id`、`status`、`category`、`format`、`lineage`、`result`（jsonb） | 料理写真の特徴の抽出結果 |

**Storage**（どちらも非公開）
- `record-images`: `<user_id>/<store_id>/<ファイル名>`
- `profile-images`: `<user_id>/<ファイル名>`

**アクセス制御（RLS）の方針**
- 自分の行: すべての操作ができる
- フォロー中の相手の行: 見るだけ（記録・写真・AI の学習状況）
- 書き込みは本人か、サーバー側の処理（Edge Function）だけ

## テスト

- **iOS**: Swift Testing で **159件**（Repository・ViewModel・写真の位置情報の読み取り・キャラクターのレベル判定など）
- **データベース**: `supabase/tests/` に、RLS・フレンド申請・ユーザー名の SQL テストと、使い捨ての PostgreSQL で実行するスクリプト
- **AI バックエンド**: ローカルでの学習→予測の確認スクリプト（`test_local.py`）と、API の動作確認スクリプト（`test_api.py`）

## プロジェクト構成

```
tkb_2623/
├── GourmetShareMap/                 # iOS アプリ
│   ├── App/                         # 起動、ログイン状態による画面の出し分け、タブ構成
│   ├── Core/                        # 画面をまたぐ状態（記録・フレンド申請）
│   ├── Features/
│   │   ├── Auth/                    # Sign in with Apple
│   │   ├── Record/                  # 登録・編集（カメラ、写真、お店の候補）
│   │   ├── Map/                     # マップ（Google Maps、ピン、絞り込み）
│   │   ├── Timeline/                # タイムライン
│   │   ├── Profile/                 # プロフィール・編集・アイコンの切り抜き
│   │   ├── Friend/                  # フレンド一覧・検索・申請
│   │   └── Grow/                    # 育てる（キャラクター、AI おすすめ）
│   ├── Repositories/                # Supabase とのやり取り
│   ├── Services/                    # 位置情報、カメラ、Google Places
│   ├── Models/                      # データの型
│   ├── Shared/                      # 共通の部品・カテゴリの色とアイコン
│   └── Supabase/                    # 接続設定
├── GourmetShareMapTests/            # iOS の単体テスト
├── supabase/
│   ├── migrations/                  # テーブル・RLS・関数の定義
│   ├── functions/
│   │   ├── ai-recommend/            # AI バックエンドへの中継
│   │   └── analyze-dish/            # 料理写真の特徴抽出
│   └── tests/                       # DB のテスト
└── mogumap_clip_lgbm/               # AI バックエンド（Cloud Run）
    ├── api.py                       # FastAPI のエンドポイント
    ├── ml.py                        # 特徴量・学習・評価・予測
    ├── recommend.py                 # Gemini と Places による候補生成
    ├── storage.py                   # モデルの保存（Cloud Storage）
    └── Dockerfile
```

## セットアップ

### iOS アプリ
Mac と Xcode が必要です。

1. `GourmetShareMap/Supabase/SupabaseConfig.swift.example` をコピーして `SupabaseConfig.swift` を作り、Supabase の URL と anon key を入れる
2. `GourmetShareMap/Services/Places/GoogleMapsConfig.swift.example` をコピーして `GoogleMapsConfig.swift` を作り、Google Maps / Places API のキーを入れる
3. `GourmetShareMap.xcodeproj` を Xcode で開き、実行する

`SupabaseConfig.swift` と `GoogleMapsConfig.swift` は `.gitignore` の対象です。キーをコミットしないでください。

### Supabase
`supabase/migrations/` の SQL を順に適用し、Edge Function をデプロイします。
- 記録・フレンド・AI 連携: [supabase/README.md](supabase/README.md)
- 料理写真の特徴抽出: [supabase/DISH_ANALYSIS.md](supabase/DISH_ANALYSIS.md)

### AI バックエンド
Cloud Run へのデプロイと必要な設定は [mogumap_clip_lgbm/REQUIREMENTS.md](mogumap_clip_lgbm/REQUIREMENTS.md) を参照してください。
