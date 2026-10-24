# Nearby Search 接続テスト（Swift）

`GoogleMapConfig.swift` の `GoogleMapConfig.apiKey` を直接参照し、
検索位置から半径1km以内の飲食店（restaurant / cafe）を距離順に最大5件出力します。
店舗ごとにPlace ID・店名・緯度経度・算出した日本語カテゴリを表示します。
範囲内に5件なければ取得できた件数のみ表示します。
Google Cloudで **Places API (New)** と請求先を有効にしてください。

カテゴリは提示された13分類に従い、`primaryType` の具体的な分類を優先します。
主カテゴリが汎用（`restaurant` など）または未分類の場合は `types` を照合します。
複数の分類に一致するときは提示された順序を優先し、どれにも一致しない場合は「その他」にします。
型名は検索フィルタには追加せず、返された店舗の分類に使用します。

出力例（架空の店舗）:

```text
[1]
Place ID: example-place-id
店名: サンプルラーメン店
緯度・経度: 35.681236, 139.767125
算出したカテゴリ: ラーメン・麺類
```

## Linux

Swiftの実行環境が必要です。リポジトリのルートで実行します。

```bash
swiftc -D PLACES_API_CLI -parse-as-library \
  GourmetShareMap/Services/Places/GoogleMapConfig.swift \
  GourmetShareMap/Services/Places/PlacesAPITest.swift \
  -o /tmp/PlacesAPITest &&
/tmp/PlacesAPITest
```

引数を省略すると、GeoClueの `where-am-i` を通して現在地を取得します（最大30秒）。
GeoClueのデモツールとcoreutilsの `stdbuf` が必要です。
Ubuntu / Debianでは次のパッケージをインストールしてください。

```bash
sudo apt install geoclue-2.0 geoclue-2-demo coreutils
```

デスクトップの設定で位置情報を許可してください。取得精度はGeoClueの位置情報ソースに依存します。
位置情報の許可エージェントがないデスクトップ環境では、別ターミナルでGeoClueのデモエージェントを起動してください
（配置は環境により `/usr/lib/geoclue-2.0/demos/agent` または `/usr/libexec/geoclue-2.0/demos/agent`）。
位置情報を取得できなければエラー終了し、別の位置へ自動的に切り替えることはありません。

WSL・コンテナ・SSHなど、現在地を取得できない環境では、テスト用の緯度・経度を明示できます。
次の座標は東京駅付近の例であり、現在地ではありません。

```bash
/tmp/PlacesAPITest 35.681236 139.767125
```

## Windows

[Swift公式のWindows導入手順](https://www.swift.org/install/windows/)に従ってSwiftと開発ツールをインストールしてください。
Windowsでは自動取得に対応していないため、緯度・経度を指定します。
リポジトリのルートでPowerShellから実行してください。

```powershell
swiftc -D PLACES_API_CLI -parse-as-library .\GourmetShareMap\Services\Places\GoogleMapConfig.swift .\GourmetShareMap\Services\Places\PlacesAPITest.swift -o "$env:TEMP\PlacesAPITest.exe"
if ($LASTEXITCODE -eq 0) {
    & "$env:TEMP\PlacesAPITest.exe" 35.681236 139.767125
}
```

## 補足

- APIキーを変更したら再コンパイルしてください。キーを含む実行ファイルは共有しないでください。
- `--help` では通信せず使い方を表示します。正常終了はコード0、設定・位置取得・通信・APIエラーはコード1です。
- `PLACES_API_CLI` を指定したときだけ有効になり、通常のiOSアプリには影響しません。アプリ本体への位置取得・検索の組み込みは含みません。
- 実行時はNearby Search (New)を1回呼び出すため、API利用料金が発生する場合があります。
- HTTP 403の場合はAPIの有効化、請求先、キーのAPI制限とアプリケーション制限を確認してください。iOS用の制限を付けたキーはWeb API呼び出しに使えない場合があります。

[Nearby Search公式仕様](https://developers.google.com/maps/documentation/places/web-service/nearby-search)
