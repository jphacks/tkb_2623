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

### Swift Testing

MacのXcodeで`SupabaseConfig.swift.example`と`GoogleMapConfig.swift.example`をもとに
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
- 実際のSupabaseプロジェクトへの操作、iOSアプリ全体のビルド、Xcodeシミュレータテストは未実行です。
