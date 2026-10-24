//
//  StoreSearchService.swift
//  GourmetShareMap
//

import CoreLocation
import DeveloperToolsSupport

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

    /// 候補リストで店舗アイコンとして使う画像（`ShopCategory` の分類名に対応。Assets.xcassets）。
    /// 専用アイコンのないカテゴリ（中華・アジア・エスニック・その他）は `others` を使う。
    var iconImage: ImageResource {
        switch category {
        case "和食": .sushi
        case "ラーメン・麺類": .ramen
        case "焼肉・肉料理": .steak
        case "カレー": .curry
        case "洋食・西洋料理": .pizza
        case "ファストフード・食堂": .hamburger
        case "カフェ・喫茶": .cafe
        case "パン": .bakery
        case "スイーツ": .sweets
        case "居酒屋・バー": .bar
        default: .others
        }
    }
}
