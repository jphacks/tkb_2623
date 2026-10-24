# AI店舗推薦

`POST /functions/v1/recommend-shop`。ログインユーザー本人の`store`だけを使用します。
Geminiで履歴の嗜好分析・検索語生成を行い、Places API (New)で店舗の検索・実在・営業状態・検索範囲を検証します。
DB変更、履歴の保存、画面・現在地取得は含みません。

## 入出力

AuthorizationにSupabase AuthのユーザーJWTを指定します。ユーザーIDを本文で受け取りません。

```json
{
  "genre": "あっさりしたラーメン",
  "latitude": 35.6812,
  "longitude": 139.7671,
  "area": "渋谷駅"
}
```

- `genre`: 空白以外の文字が必要。前後空白除去後に最大200 UTF-16コード単位。
- 緯度・経度: 必須の有限な数値。緯度は-90〜90、経度は-180〜180。
- `area`: 任意の文字列、最大200 UTF-16コード単位。省略・空白時は現在地から半径2km。
  指定時はPlaces Text Searchで特定した地点から半径2km。地名・駅名を入力し、
  「徒歩15分」「半径500m」等の距離指定や行政境界による検索は扱いません。
- 同一IDの地名候補を統合し、全候補が相互に500m以内なら最初の地点を採用します。
  それ以外は候補名・住所を含む`AREA_AMBIGUOUS`を返します。現在地へ切り替えません。

```json
{
  "recommendation": {
    "place_id": "取得したGoogle Place ID",
    "name": "店舗名",
    "latitude": 35.0,
    "longitude": 139.0
  },
  "attributions": [
    {
      "provider": "Google Maps",
      "name": "店舗名",
      "url": "https://maps.google.com/?cid=123"
    }
  ]
}
```

店舗オブジェクトは4項目だけで、`reason`はありません。名前・ID・座標・Maps URLは
Place Detailsの取得結果を使用します。外部提供者の出典があれば`attributions`に追加します。
表示画面を追加する際は、結果の近くにGoogle Mapsの帰属表示・リンクと必要な提供者出典を
表示してください。Placesのデータを地図に載せる場合はGoogle Mapを使用します。
口コミ本文は返しません。データの出典と表示要件は
[Places APIポリシー](https://developers.google.com/maps/documentation/places/web-service/policies)を参照してください。

エラー形式:

```json
{
  "error": {
    "code": "AREA_AMBIGUOUS",
    "message": "地名の候補が複数あります。住所や駅名を詳しく指定してください。",
    "candidates": [{ "name": "駅名", "address": "住所" }]
  }
}
```

| HTTP | code                                 | 意味                               |
| ---- | ------------------------------------ | ---------------------------------- |
| 400  | INVALID_INPUT                        | 入力不正（本文は最大16,384文字）   |
| 401  | UNAUTHORIZED                         | JWTなし・無効・ユーザー未認証      |
| 404  | NO_RECOMMENDATION                    | 指定範囲内に検証可能な店舗なし     |
| 405  | METHOD_NOT_ALLOWED                   | POST以外                           |
| 422  | AREA_NOT_FOUND / AREA_AMBIGUOUS      | 地名を特定できない                 |
| 500  | CONFIGURATION_ERROR / INTERNAL_ERROR | 設定不足・内部エラー               |
| 502  | UPSTREAM_ERROR / INVALID_AI_RESPONSE | 外部API・応答形式のエラー          |
| 502  | GEMINI_BILLING_REQUIRED              | Geminiの前払いクレジット不足       |
| 502  | GEMINI_MODEL_UNAVAILABLE             | 指定したGeminiモデルを利用できない |
| 502  | GEMINI_QUOTA_EXCEEDED                | Gemini APIのクォータ超過           |
| 504  | TIMEOUT                              | 1通信15秒・全体60秒の期限超過      |

外部APIの本文、キー、JWT、履歴・メモ・位置情報はエラーメッセージやログへ出力しません。

## 選定方法

本人の履歴を評価降順（NULLは最後）、来店回数降順、作成日時降順、ID昇順で最大100件取得し、
メモを各1,000 UnicodeコードポイントまでGeminiへ渡します。氏名・メール・ユーザーID・座標はGeminiへ送りません。
検索中心座標はPlaces APIへ渡します。
過去の店舗名・評価・メモ等を外部サービスへ送信する機能のため、
提供開始時のプライバシー説明に反映してください。実ユーザーの履歴には、有効な請求先を紐付けた
GeminiのPaid Servicesを使用してください。
[Geminiのデータ利用条件](https://ai.google.dev/gemini-api/terms)を参照してください。

Geminiの構造化出力で検索語・キーワードを生成します。検索語には希望ジャンルを保持し、
履歴なしの場合はジャンルのみを検索語とします。Gemini呼び出しは1回で、検索ツールを指定しません。
Placesで取得した口コミ等はGeminiへ送信せず、今回の採点内で参照します。
APIエラー・タイムアウト・クォータ超過はエラーとして返し、自動再試行しません。

Text Searchの最初の最大20件から飲食施設を抽出し、Haversineの直線距離が2,000m以内だけを対象にします。
休業・閉業、必須項目不足、重複を除き、未訪問店舗も同様に採点します。

- 嗜好: 店名・英語タイプ名・日本語カテゴリ・価格帯ラベル・口コミへのキーワード部分一致数 / キーワード数（45%）。NFKC正規化・小文字化で比較。
- 評価: Google評価 / 5（30%）。
- 距離: `1 - 距離 / 2000`（25%）。

キーワードがない場合は嗜好の重みを、不明・不正な評価の場合は評価の重みを除き、残った重みで正規化します。
同点は距離昇順、Place ID昇順。Place DetailsでID・位置・営業状態・飲食施設種別と出典を再照合します。
404・410や無効な店舗は次候補へ進みます。その他のAPI障害はエラーとして返します。
候補を使い切った場合は推薦不可で、検索範囲を拡大しません。自動再試行・永続キャッシュはありません。

## ローカル実行・設定

### Linuxで推薦精度を確認するCLI

このCLIは本番と同じ推薦処理でGemini・Placesに実通信します。Mac・Xcode・Docker・Supabase CLIは不要で、Deno 2と外部APIのキーが必要です。Authと履歴にはローカルのテストデータを使用するため、Supabaseの実認証・実DBの結合確認は別途行います。Google APIの利用料金が発生します。

1. 以下のSwiftファイルの`static let apiKey`へキーを設定します。両ファイルはGit管理対象外です。Geminiの実ファイルはiOSアプリのビルド対象からも除外しています。キーをチャットへ貼り付ける必要はありません。
   - `GourmetShareMap/Services/Gemini/GoogleGeminiConfig.swift`
   - `GourmetShareMap/Services/Places/GoogleMapConfig.swift`
2. `input.example.json`のジャンル・地名を変更します。現在地中心の検索を試す場合は`area`を削除し、検証したい緯度・経度を設定します。
3. リポジトリルートで以下を実行します。

```sh
deno run \
  --allow-env=GEMINI_API_KEY,GOOGLE_PLACES_API_KEY,GEMINI_MODEL \
  --allow-read=supabase/functions/recommend-shop,GourmetShareMap/Services/Gemini/GoogleGeminiConfig.swift,GourmetShareMap/Services/Places/GoogleMapConfig.swift \
  --allow-net=generativelanguage.googleapis.com,places.googleapis.com \
  supabase/functions/recommend-shop/live_check.ts \
  supabase/functions/recommend-shop/input.example.json
```

環境変数が設定済みの場合は環境変数を優先します。従来の`supabase/.env.local`を使う場合は`--env-file=supabase/.env.local`を追加できます。Swiftファイルは実行時に読み取り、キーをログ・一時ファイルへ書き出しません。デプロイするEdge Functionは従来どおりSupabase Secretsを使用します。

結果にはHTTPステータス・所要時間・推薦店舗・Mapsリンクが出力されます。履歴未指定時は履歴なしで実行します。嗜好を比較する場合は、次の形式の配列をJSONファイルに保存し、第2引数として追加します。別のディレクトリに置く場合は、そのファイルを`--allow-read`にも指定してください。履歴は評価・来店回数・作成日時の優先順で並べてください。

```json
[
  {
    "name": "テスト用の塩ラーメン店",
    "category": "ラーメン",
    "reputation": 5,
    "repeat_num": 8,
    "memo": "あっさりしたスープが好き"
  }
]
```

同じジャンル・地名について履歴なし／ありを比較し、Mapsリンクでジャンル・距離・営業状態・好みに合うかを確認します。生成・検索結果は変動するため、数回試した結果で判断してください。通常のモックテストはこの実通信CLIを実行しません。

### Supabaseを起動して実行

Supabase CLI、DockerとDeno 2を用意します。リポジトリルートから実行してください。

```sh
supabase start
cp supabase/functions/recommend-shop/.env.example supabase/.env.local
# supabase/.env.local にローカルでキーを設定
supabase functions serve recommend-shop --env-file supabase/.env.local
```

`SUPABASE_URL`と`SUPABASE_ANON_KEY`はEdge Runtimeから注入されます。
`SUPABASE_SERVICE_ROLE_KEY`は使用しません。`supabase/config.toml`の`verify_jwt = false`は
ゲートウェイのJWT検証を省略する設定です。関数内では必ずAuthの`/auth/v1/user`へJWTを渡して
認証し、そのユーザーのJWTでRLSを適用して履歴を読み取ります。この設定により非対称署名のJWTにも対応し、
認証エラーを共通のJSON形式で返します。

必要な外部設定:

- Gemini APIの利用可能なプロジェクトとサーバー用キー。
- Places API (New)と請求先を有効化したサーバー用キー。既存iOS用キーとは分けて管理。
- `GEMINI_MODEL`は任意。省略時`gemini-3.1-flash-lite`。この環境の実API確認で約8秒で推薦まで完了したモデルを初期値にしています。2.5 Flashは新規ユーザーには利用不可、3.8 Flashは1通信15秒の期限を超過しました。3.8 Flashを指定した場合は思考量をLOWに設定し、いずれのモデルも出力上限を1,024トークンにしています。
- `reviews`等を含むField Maskで検索するため、そのフィールドに応じたPlaces利用料金が発生します。

認証済みのローカルユーザーJWTを環境変数`ACCESS_TOKEN`に設定して、明示的な実API確認を行えます。
GeminiとPlacesへの課金対象リクエストになります。

```sh
curl --fail-with-body http://127.0.0.1:54321/functions/v1/recommend-shop \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  --data '{"genre":"ラーメン","latitude":35.6812,"longitude":139.7671}'
```

## デプロイ手順

実装作業では本番デプロイしません。デプロイする場合は、対象プロジェクトを明示して実行します。
`supabase/.env.local`はGit管理対象外です。キーをコマンド引数に直接記載しないでください。

```sh
supabase secrets set --project-ref "$PROJECT_REF" --env-file supabase/.env.local
supabase functions deploy recommend-shop --project-ref "$PROJECT_REF"
```

## Swiftからの利用

ログイン後、MainActor上で呼び出します。通信・認証・キャンセルのエラーは呼び出し元へ伝播します。
APIのエラーは`RecommendationError.api(statusCode:error:)`でコード・メッセージ・地名候補を取得できます。

```swift
let result = try await RecommendationRepository().recommend(
    RecommendationInput(genre: "ラーメン", latitude: 35.6812, longitude: 139.7671, area: "渋谷駅")
)
let shop = result.recommendation
// shop.placeID / shop.name / shop.latitude / shop.longitude
// 表示するときは result.attributions も一緒に使用する。
```

## モックテスト

以下はGemini・Places・実Supabaseへ接続しません。Denoテストはネットワーク・環境変数の許可も不要です。

```sh
deno task --config supabase/functions/recommend-shop/deno.json check
deno task --config supabase/functions/recommend-shop/deno.json test
bash supabase/tests/check_recommendation_swift_local.sh
```

SwiftのローカルテストにはSwift 6.2以上とPython 3が必要です。初回だけSupabase Swift SDK 2.55.4の
依存解決が必要です。ビルド成果物は一時ディレクトリに置き、実アプリのモデル・Repositoryとテストを使用します。
XcodeのMainActor既定設定も再現します。オフラインでSDKを指定する場合は`RECOMMENDATION_CHECK_SDK_PATH`、
一時作業ディレクトリを変更する場合は`RECOMMENDATION_CHECK_BUILD_DIR`を指定してください。
Macでは通常のXcodeテストターゲットの`RecommendationRepositoryTests`でも実行できます。
iOS全体のビルド・シミュレータ実行はMacで別途確認します。
