# 店舗画像Repository

既存の `schema.sql` と `storage.sql` が適用済みであることを前提とします。
本機能のためのスキーマ変更はありません。既存DBでschema.sqlを再実行しないでください。
ログイン済みユーザーにはpublic.userの行と、本人所有のstoreが必要です。

## 使用方法

MainActor上で呼び出します。UIでJPEG/PNGにエンコードしてから渡してください。
formatはMIME型・拡張子の指定であり、画像データのデコードや変換は行いません。

```swift
let repository = ImageRepository()
let image = try await repository.uploadImage(data: jpegData, storeID: storeID, format: .jpeg)
let url = try await repository.signedURL(imageID: image.id) // 有効期限3600秒
try await repository.deleteImage(imageID: image.id)
```

- `record-images` は非公開バケットです。公開URLではなく署名付きURLを取得します。
- image行には `<user_id>/<store_id>/<UUID>.jpg` または `.png` のパスを保存します。
- アップロードと削除は本人所有の店舗のみ。フレンドの画像は既存RLSに従ってURL取得できます。
- 行登録に失敗するとアップロードしたファイルを削除します。後始末も失敗すると
  `ImageRepositoryError.cleanupFailed` に対象パス・登録エラー・後始末エラーを保持します。
- 削除はStorage→DBの順です。DB削除失敗時は同じimageIDで再試行してください。
  Storage削除の空配列レスポンス、または404ならDB行の削除に進みます。権限エラーは無視しません。
- StorageとDBは別リクエストで、原子的な処理ではありません。アプリ強制終了や、通信断で
  サーバー側の結果が不明な場合まで整合性を保証するものではありません。

## 動作確認

Swift 6.2以上・Python 3を用意し、リポジトリのルートで実行します。
初回はSupabase Swift SDK 2.55.4と依存ライブラリを取得します。

```sh
bash scripts/check_repositories.sh
bash supabase/tests/check_repository_db.sh
```

前者は現行のRepository・Model・テストを一時Swiftパッケージへコピーし、
認証ストレージとHTTP通信をモックにして検証します。APIキーやSupabaseアカウントは不要です。
後者はDocker上の一時PostgreSQL 17で、本人のimage行の登録・取得・削除、フレンドの閲覧、
他人による登録・更新・削除の拒否を検証します。一時DBは終了時に削除します。

オプション: `REPOSITORY_TEST_SDK_PATH` でローカルSDKのパス、
`REPOSITORY_TEST_BUILD_DIR` でビルドキャッシュ先を指定できます。
同じキャッシュ先を使うテストは同時に実行しないでください。

MacではGourmetShareMapTestsのImageRepositoryTestsをXcodeから実行できます。
アプリ全体のビルドにはSupabaseConfig.swiftのローカル設定が必要です。

Storageの実サービス・Storage RLS、実Supabase Auth、iOSアプリ全体のビルドは
このCLIテストの検証対象に含みません。

## このブランチの検証結果

- Swift 6.4.1 / Linux、Supabase SDK 2.55.4で通信モックテスト15件成功
  （パラメーター化したテストを展開すると20シナリオ）。
- PostgreSQL 17の一時DBでimage行の登録・取得・削除と、本人・フレンド・他人のRLSテスト成功。
- 実Storageサービスへの接続、実Supabaseへの操作とiOSアプリ全体のビルドは未実行。
