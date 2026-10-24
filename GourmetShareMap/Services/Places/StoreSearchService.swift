//
//  StoreSearchService.swift
//  GourmetShareMap
//

import CoreLocation

/// 位置を受け取って周辺の店舗候補を返すインターフェース。
///
/// - 候補が 0 件のときはエラーではなく空配列を返す。
/// - 通信失敗・API エラーなどは throw する。UI 側は `localizedDescription` をそのまま表示する。
/// - 位置の決定（EXIF 優先・なければ現在地）は呼び出し側（RecordViewModel）で行う。
protocol StoreSearchService {
    func searchNearbyStores(around coordinate: CLLocationCoordinate2D) async throws -> [NearbyShop]
}

/// Places API (New) の Nearby Search（`findNearestShop`）で検索する本番実装。
struct PlacesStoreSearchService: StoreSearchService {
    func searchNearbyStores(around coordinate: CLLocationCoordinate2D) async throws -> [NearbyShop] {
        try await findNearestShop(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

extension NearbyShop: Identifiable {
    var id: String { placeID }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// 候補リストで店舗アイコンとして使う SF Symbol（`ShopCategory` の分類名に対応）。
    var symbolName: String {
        switch category {
        case "ラーメン・麺類": "takeoutbag.and.cup.and.straw.fill"
        case "カフェ・喫茶": "cup.and.saucer.fill"
        case "パン": "basket.fill"
        case "スイーツ": "birthday.cake.fill"
        case "居酒屋・バー": "wineglass.fill"
        case "焼肉・肉料理": "flame.fill"
        case "和食": "fish.fill"
        default: "fork.knife"
        }
    }
}
