# findNearestShop 接続テスト

`PlacesAPITest.swift` は引数の緯度・経度を `findNearestShop(latitude:longitude:)` に渡し、
戻り値の `[NearbyShop]` を `print(shops)` でそのまま出力します。
該当店舗を距離順に最大5件出力し、なければ `[]` を出力します。
引数・通信・APIエラー時は標準エラーに出力し、終了コード1で終了します。

`GoogleMapsConfig.swift` にAPIキーを設定し、Google Cloudで **Places API (New)** と請求先を有効にしてください。

## Linux

Swift環境で、リポジトリのルートから実行します。

```bash
swiftc -D PLACES_API_CLI -parse-as-library \
  GourmetShareMap/Services/Places/GoogleMapsConfig.swift \
  GourmetShareMap/Services/Places/PlaceCategoryClassifier.swift \
  GourmetShareMap/Services/Places/FindNearestShop.swift \
  GourmetShareMap/Services/Places/PlacesAPITest.swift \
  -o /tmp/PlacesAPITest &&
/tmp/PlacesAPITest 35.713329 139.7617112
```

## Windows（PowerShell）

Swift環境で、リポジトリのルートから実行します。

```powershell
swiftc -D PLACES_API_CLI -parse-as-library .\GourmetShareMap\Services\Places\GoogleMapsConfig.swift .\GourmetShareMap\Services\Places\PlaceCategoryClassifier.swift .\GourmetShareMap\Services\Places\FindNearestShop.swift .\GourmetShareMap\Services\Places\PlacesAPITest.swift -o "$env:TEMP\PlacesAPITest.exe"
if ($LASTEXITCODE -eq 0) {
    & "$env:TEMP\PlacesAPITest.exe" 35.713329 139.7617112
}
```

## 戻り値

半径1km以内の飲食店（restaurant / cafe）を近い順に最大5店舗返します。
5店舗未満の場合は取得できた件数だけ返します。
`NearbyShop` は次のプロパティを持ち、表示はアプリ側で行います。

- `placeID: String`
- `name: String`
- `latitude: Double`
- `longitude: Double`
- `category: String`（日本語）

カテゴリは `PlaceCategoryClassifier.swift` の13分類に従い、具体的な `primaryType` を優先し、
該当しなければ `types` を提示順に照合します。未分類は「その他」です。

APIキーを変更したら再コンパイルしてください。キーを含む実行ファイルは共有しないでください。
実行時にNearby Searchを1回呼び出すため、API利用料金が発生する場合があります。
`PLACES_API_CLI` はCLI実行時だけ指定してください。通常のiOSアプリにはテストのエントリーポイントを追加しません。
