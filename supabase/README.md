# AIバックエンド連携 (ai-recommend Edge Function)

`supabase/functions/ai-recommend/` は、iOSの「AIを育てる」タブからのレコメンド要求を
Cloud Run上のAIバックエンド(`mogumap_clip_lgbm/`)へ中継するEdge Function。
APIキーをアプリに埋め込まないため、iOSはCloud Runを直接呼ばずこのEdge Function経由で呼ぶ。
詳細は [mogumap_clip_lgbm/REQUIREMENTS.md](../mogumap_clip_lgbm/REQUIREMENTS.md) を参照。

デプロイと環境変数設定:

```sh
supabase functions deploy ai-recommend
supabase secrets set AI_BACKEND_URL="https://<Cloud RunのURL>"
supabase secrets set AI_BACKEND_API_KEY="<Cloud Run側のAI_BACKEND_API_KEYと同じ値>"
```

`AI_BACKEND_API_KEY`はGCP Secret Manager上の`ai-backend-api-key`と同じ値を使う。

本マイグレーション(`20261024100000_ai_backend_schema.sql`)は`store`テーブルへの
`google_rating`/`price_level`/`review_count`カラム追加と、`ai_model_status`テーブルの
新規作成を行う。既存の保存機能(下記)への影響はない。

# 店舗記録の保存

`RecordRepository`は既存の **`public.store`（単数形）** に保存します。
テーブル・カラム・制約・RLSの変更や追加マイグレーションはありません。
既存のフレンド共有と画像の参照関係もそのまま使用します。

## DBの前提

既存の`schema.sql`が適用済みであることを前提とします。
`store.user_id`は`public."user".id`を参照するため、ログインしたユーザーの行が
`public."user"`に登録済みである必要があります。未登録の場合は外部キーエラーを返します。
Repositoryはプロフィールを自動作成しません。

今回の保存機能のためにSQLを適用する必要はありません。
既存の`schema.sql`はテーブル削除などを含むため、既存DBへ再実行しないでください。
本番DBへの操作は行っていません。

## Swiftからの利用

ログイン後、MainActor上で呼び出します。

```swift
let repository = RecordRepository()
let saved = try await repository.saveStore(
    StoreSaveInput(
        name: "喫茶サンプル",
        category: "カフェ・喫茶",
        reputation: 4,
        googlePlaceID: "Google Placesから取得したID",
        memo: "また行きたい",
        repeatNum: 1,
        latitude: 35.6812,
        longitude: 139.7671
    )
)
```

- `id`指定時は本人の既存行を更新します。対象がない場合は`StoreSaveError.notFound`です。
- `id`なし・Google店舗IDありの場合は、本人の該当レコードを検索して、1件ならそのIDで更新、0件なら新規登録します。
- 該当レコードが複数ある場合は`StoreSaveError.ambiguousGooglePlaceID`を返します。編集対象の`id`を指定してください。
- 両方なしの場合は毎回新規登録します。手入力店舗の編集では保存結果の`id`を渡してください。
- 全項目の上書きです。評価・メモ・Google店舗IDの`nil`はNULLとして送信します。
- 訪問回数は初期値1で、指定値をそのまま保存します。自動加算はしません。
- `user_id`はセッションから取得します。`id`・`created_at`は保存ペイロードに含めません。
- 既存DBにはユーザーIDとGoogle店舗IDの組の一意制約がありません。検索と保存は別リクエストのため、
  同時保存で重複が発生する可能性があります。DB定義を変えずに原子的なupsertや重複防止は保証できません。
- ID指定の更新では、Google店舗IDが重複していても指定行だけを更新します。自動統合はしません。
- 保存入力は前回決定した仕様（カテゴリ・座標必須、自分の評価は1〜5の整数、訪問回数は初期1）を維持します。
  既存DBの仕様（カテゴリ・座標NULL、小数評価、訪問回数0）も読み取れるよう、戻り値は対応する型にしています。

## テスト

### ローカルでテーブル生成・疑似データを確認

Dockerを起動し、リポジトリのルートから実行します。SupabaseのアカウントやAPIキーは不要です。

```sh
bash supabase/tests/check_store_local.sh
```

一時PostgreSQL 17にAuth相当の最小構成と既存`schema.sql`を適用し、テーブル一覧・`store`の
カラムと制約・疑似店舗2件を表示します。保存とRLSのSQLテストも実行し、最後に「成功」と表示されればOKです。
初回はDockerイメージのダウンロードが発生します。

DBのポートは公開せず、終了時に一時DB・コンテナを削除します。既存のローカルDBや本番DBには接続しません。
これはPostgreSQLでのスキーマ・データ・RLSの確認です。Supabase Auth本体やSwiftからの実通信は検証しません。

### Swift Testing

MacのXcodeで`SupabaseConfig.swift.example`と`GoogleMapsConfig.swift.example`をもとに
ローカル設定ファイルを準備し、依存パッケージを解決してから、
`GourmetShareMapTests`の`RecordRepositoryTests`を実行してください。
テストは専用のインメモリ認証ストレージとURLProtocolを使い、実際の認証・DBへ接続しません。
設定ファイルの値はこのテストでは使用しません。

CLIで実行する場合は、利用できるシミュレータを`xcodebuild -showdestinations`で確認して指定します。

```sh
xcodebuild -project GourmetShareMap.xcodeproj -scheme GourmetShareMap -showdestinations
xcodebuild test -project GourmetShareMap.xcodeproj -scheme GourmetShareMap \
  -destination 'platform=iOS Simulator,id=<利用可能なシミュレータUUID>' \
  -only-testing:GourmetShareMapTests/RecordRepositoryTests
```

### Nearby Searchと店舗保存の結合テスト

Docker・Swift 6.2以上・Python 3・curlを用意し、リポジトリのルートから実行します。
初回はSupabase SDK 2.55.4の依存解決・ビルドと、PostgRESTイメージの取得が必要です。

実Google APIから最寄り店舗を取得する場合:

```sh
bash supabase/tests/check_nearby_store_local.sh --live 35.713329 139.7617112
```

APIキーは`GOOGLE_MAPS_API_KEY`環境変数、または既存の`GoogleMapsConfig.swift`に設定します。
実GoogleのNearby Searchを1回呼び出すため、Places API (New)を有効にしたキーが必要で、
API利用料金が発生する場合があります。キーはログや一時ソースへ出力しません。

GoogleのAPIキーなしで結合部分を検証する場合:

```sh
bash supabase/tests/check_nearby_store_local.sh --mock
```

両モードとも、アプリ本体の`NearbyShopClient`・カテゴリ判定・`RecordRepository`を使用します。
半径1km以内の飲食店・カフェを距離順で検索し、返された最大5件の座標から直線距離が最小の店舗を選びます。
モックモードでは意図的に最寄り店舗を先頭以外へ置き、店舗の選択も検証します。

検証する流れ:

1. Nearby Search → 最短距離の店舗選択。
2. その店舗のGoogle店舗ID・店名・カテゴリ・店舗の座標を`RecordRepository`で保存。
3. 実PostgREST・PostgreSQLから再取得し、所有者・保存値・件数1件を照合。
4. IDを渡さず同じ店舗を再保存し、訪問回数2・メモNULL・IDと作成日時保持・重複なしを確認。
5. モックモードでは、検索0件・Google APIエラー時に保存へ進まないことも確認。

実APIの検索結果が0件の場合は、保存せず終了コード1で理由を表示します。別の座標で再実行してください。
最寄り店舗の名前・Google店舗ID・距離・最終DB行と「成功」が出れば確認完了です。

Authには疑似ユーザーと署名済みのテスト用JWTを使用し、Apple認証・Supabase Auth本体は起動しません。
SDKの`/rest/v1`プレフィックスをテスト用URLProtocolで外して、ローカルの実PostgRESTへHTTP転送します。
DB側は既存の`schema.sql`を使用し、RLSが有効な`authenticated`ロールでアクセスします。
PostgRESTは127.0.0.1のランダムポートのみ公開し、終了時にDB・PostgREST・ネットワークを削除します。
ビルド結果のみOSの一時ディレクトリにキャッシュします。本番DBの設定は使用しません。

### DBの制約・RLS

既存スキーマを適用済みのテスト専用DBで[`tests/store.sql`](tests/store.sql)を
管理者として実行してください。CLIなら次のとおりです。

```sh
psql "$TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/store.sql
```

ID・作成日時の保持、既存のNULL・小数評価・訪問回数の初期値、他人への更新・なりすまし登録の拒否、
フレンド共有と所有者による検索条件を確認します。重複がDBで許容される既存仕様も確認します。
各ユーザーの検証では`authenticated`ロールへ切り替え、すべてのテストデータを最後にROLLBACKします。
エラー時はROLLBACKしてから再実行してください。

Swiftの通信モックはリクエストとレスポンスを検証し、実DBの制約・RLSは上記SQLで検証します。
iOSアプリ全体のビルドとシミュレータテストにはMacとXcodeが必要です。

### 実装時の検証

- Supabase SDK 2.55.4を使用したLinuxの一時Swiftパッケージで通信モックテスト15件を実行。
  アプリと同じMainActor既定設定を使い、接続マネージャーのみテスト用に差し替えています。
- 一時PostgreSQL 17上で、Authの最小構成と変更していない既存`schema.sql`を適用し、
  `tests/store.sql`の保存・フレンド共有・RLSの検証が成功しました。
- Nearby Searchの結合テストは、実Google APIモードとGoogleモックモードの両方で、
  最寄り店舗の選択・ローカル実DBへの登録・再取得・同じ行の更新が成功しました。
- 実際のSupabaseプロジェクトへの操作、iOSアプリ全体のビルド、Xcodeシミュレータテストは未実行です。

## マップ・プロフィール向けの店舗一覧

```swift
let records = try await RecordRepository().fetchStores()
```

ログインユーザー自身の店舗を `created_at` 降順・同日時は `id` 昇順で返します。
返却型は保存時と共通の `[StoreRecord]` です。座標がNULLの記録も返すため、
マップでは座標のある記録を選び、プロフィールでは全記録を表示できます。
0件は空配列、認証・通信・DB・デコードの失敗はthrowします。

Supabaseの標準返却上限1000件に合わせ、1000件ずつ取得します。
サーバーの「Max Rows」は1000以上を前提とします。ページ取得中の並行更新について
スナップショット一貫性は保証しません。

Swift 6.2以上・Python 3で、現行ソースの保存・一覧テストをLinux/Macから実行できます。
初回はSDK 2.55.4の依存解決が必要です。実際の認証・DBへの接続やAPIキーは不要です。

```sh
bash scripts/check_repositories.sh
bash supabase/tests/check_repository_db.sh
```

後者はDocker必須で、一時PostgreSQL 17に既存schema.sqlを適用し、保存・一覧・RLSを検証します。
一時DBは終了時に削除し、既存DBは変更しません。Storageサービスは起動しません。

`REPOSITORY_TEST_SDK_PATH` でローカルSDK、`REPOSITORY_TEST_BUILD_DIR` でビルドキャッシュ先を
指定できます。同一キャッシュ先での同時実行は避けてください。
Xcodeでは既存RecordRepositoryTestsに追加した一覧テストも実行できます。

### このブランチの検証結果

- Swift 6.4.1 / Linux、Supabase SDK 2.55.4で通信モックテスト20件成功（既存保存15件＋一覧5件）。
- PostgreSQL 17の一時DBで保存・一覧の所有者条件・並び順・RLSのSQLテスト成功。
- 実Supabaseへの操作とiOSアプリ全体のビルドは未実行。

### 統合時の確認

最新mainと元のPR統合先 `feat/upload-shop-info` を取り込み、保存15件＋一覧5件のテストを保持しています。
画像Repositoryの利用方法は [IMAGE_REPOSITORY.md](IMAGE_REPOSITORY.md) を参照してください。
CLIの接続マネージャー差し替えは、mainで追加されたUserRepositoryからも参照できる構成にしています。

統合後の通信モックテストは35件（保存15件・一覧5件・画像15件）すべて成功しました。
一時PostgreSQLで保存・一覧・画像のSQL・RLS検証も成功しています。

## マップ画面向けの店舗一覧（自分＋フレンド）

```swift
let visible = try await RecordRepository().fetchVisibleStores()
// visible.currentUserID で自分の店舗とフレンドの店舗を出し分ける
let mine = visible.stores.filter { $0.userID == visible.currentUserID }
```

自分とフレンド（自分がフォローしている相手）の店舗を`created_at`降順・同日時は`id`昇順で返します。
フレンドの行は`store`のSELECT RLSポリシー（自分の行 or フォロー相手の行）で返るもので、
クエリ側では`user_id`で絞り込みません。`fetchStores()`との違いはこの絞り込みの有無だけです。

- 戻り値は`VisibleStores`（`currentUserID`と`[StoreRecord]`）です。認証の往復を増やさず
  所有者を判別できるよう、取得に使ったセッションのユーザーIDを同梱します。
- `fetchStores()`と同様に座標がNULLの行も返すため、ピン表示側で座標のある行を選びます。
- ページ取得・並び順・上限1000件の前提は`fetchStores()`と同じです。
- プロフィールは引き続き`fetchStores()`（自分の店舗のみ）を使用します。
- マップ画面はこのメソッドを直接呼ばず、`RecordStore.loadVisible()` 経由で読みます。
  登録画面での保存後に`RecordStore`のキャッシュが更新され、マップにもそのまま反映されます。

### 選択中の店舗の写真

```swift
let images = try await ImageRepository().fetchImages(storeID: store.id)
if let first = images.first {
    let url = try await ImageRepository().signedURL(imageID: first.id)
}
```

`created_at`昇順・同日時は`id`昇順で返すため、先頭が常に「最初の写真」になります。
フレンドの店舗でも使うため所有者チェックは行わず、本人・フレンドの行だけが返ることは
`image`のSELECT RLSポリシーが保証します。1店舗の画像は少数のためページ取得はしません
（昇順のため、仮に返却上限に達しても先頭の行は欠けません）。0件は空配列を返します。

## マップ手動確認用のシードデータ

`store`が空だとマップに何も表示されないため、文京区・谷根千の徒歩圏に8件の店舗を
登録するSQLを用意しています。手動確認専用で、自動テストではありません。

SQL先頭の`REPLACE_WITH_OWNER_UUID`・`REPLACE_WITH_FRIEND_UUID`を実際のUUIDへ
置き換えてから、RLSを通さない管理者（postgres / service_role）として実行します。
確認用: `select id, email from public."user" order by created_at;`

```sh
# いずれでも実行できる（psqlのメタコマンドを使っていない）
supabase db query --linked -f supabase/tests/seed_store.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/seed_store.sql
# もしくはダッシュボード > SQL Editor に貼り付け
```

- `owner`が「自分の店舗」、`friend`が「フレンドの店舗」として表示されます。
  両者には**双方向のフォロー関係**も張るため、どちらでログインしても
  「自分／フレンド／両方」の絞り込みを確認できます。
  1ユーザーだけで試す場合は両方に同じUUIDを入れてください（フォロー関係は作られません）。
- `google_place_id = 'seed-shared-ramen'`の行をownerとfriendの両方に入れており、
  「自分とフレンドの両方が登録した店舗」のピンバッジを確認できます。
- 全ピンが1画面に収まるよう、徒歩圏（約1km四方）に配置しています。
- `category`は`PlaceCategoryClassifier.categoryRules`の名称をそのまま使い、
  和食／ラーメン・麺類／焼肉・肉料理／カフェ・喫茶／パン／スイーツ／居酒屋・バーの7分類を含みます。
- `reputation`・`repeat_num`は値を散らし、`reputation`がNULLの行と`memo`がNULLの行を
  1件ずつ含めて、任意項目の表示を確認できるようにしています。
- 行はCOMMITして残します。片付けはSQL末尾のDELETE（`google_place_id`が`seed-%`）を
  参照してください。本番DBでは実行しないでください。

### このタスクの検証結果

- ローカルの一時PostgreSQL 17に`migrations/20261024025750_initial_schema.sql`を適用し、
  シードの登録・NULL項目・カテゴリ分類を確認しました。`authenticated`ロールでも参照でき、
  ピンの最大距離は約900m以内でした。
- 開発用Supabaseプロジェクトに対しても`supabase db query --linked`で実行し、
  シード8件・フォロー2件が入ったことを確認しました（既存の実データ1件は変更していません）。
- Swift側（`fetchVisibleStores()` / `fetchImages(storeID:)`）はマップ画面と合わせて
  シミュレータ向けビルドが成功しています。

## フレンド申請・承認（user_name 検索）

### 手動で適用する migration

Supabaseダッシュボード > SQL Editor で、次の順に実行してください。

1. `migrations/20261024150000_user_name_default.sql` — user_name の自動採番・既存行の補完・NOT NULL / 形式チェック
2. `migrations/20261024150100_friend_request.sql` — friend_request テーブル・申請/承認関数・friend の直接 insert ポリシー削除
3. `migrations/20261024150200_friend_search.sql` — user_name 完全一致検索・申請者の参照権限・profile-images の参照ポリシー

### ローカルでの確認

Dockerを起動し、リポジトリのルートから実行します。

```sh
bash supabase/tests/check_friend_db.sh
```

一時PostgreSQL 17に `migrations/` を順に適用し（Auth・Storageは最小構成のスタブ）、
`tests/friend_user_name.sql`・`tests/friend_request.sql`・`tests/friend_search.sql` を実行します。
既存データの補完は、user_name 必須化の前に `tests/friend_legacy_seed.sql` を投入して確認します。
