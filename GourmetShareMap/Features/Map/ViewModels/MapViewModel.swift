//
//  MapViewModel.swift
//  GourmetShareMap
//

import Combine
import CoreGraphics
import Foundation

enum ShopCategory: String, CaseIterable, Identifiable {
    case all = "すべて"
    case ramen = "ラーメン"
    case chinese = "中華"
    case western = "洋食"
    case cafe = "カフェ"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .all: "square.grid.2x2"
        case .ramen: "takeoutbag.and.cup.and.straw.fill"
        case .chinese: "frying.pan.fill"
        case .western: "fork.knife"
        case .cafe: "cup.and.saucer.fill"
        }
    }
}

enum OwnerFilter: String, CaseIterable, Identifiable {
    case me = "自分"
    case friend = "フレンド"
    case both = "両方"

    var id: String { rawValue }
}

enum ShopOwner {
    case me
    case friend
}

struct MapLandmark: Identifiable {
    let id = UUID()
    let name: String
    let relativePosition: CGPoint
}

struct MapShop: Identifiable {
    let id = UUID()
    let name: String
    let category: String
    let rating: Double
    let repeatCount: Int
    let owner: ShopOwner
    /// フレンドも訪問済みで、ピンにフレンドアイコンを重ねて表示するかどうか。
    let sharedWithFriend: Bool
    // TODO: Google Maps API導入後、CLLocationCoordinate2D(緯度経度)に置き換える。
    // 現状は地図が未実装のため、プレースホルダー上の相対座標(0〜1)で仮配置している。
    let relativePosition: CGPoint
}

@MainActor
final class MapViewModel: ObservableObject {
    @Published var selectedCategory: ShopCategory = .all
    @Published var ownerFilter: OwnerFilter = .both
    @Published var selectedShopID: MapShop.ID?

    let landmarks: [MapLandmark]
    @Published private(set) var shops: [MapShop]

    // TODO: 店舗/訪問記録テーブルにデータが入り次第、StoreRepository経由の取得に差し替える。
    // 現状はDBが空のため仮データを表示している。
    init(shops: [MapShop] = MapMockData.shops, landmarks: [MapLandmark] = MapMockData.landmarks) {
        self.shops = shops
        self.landmarks = landmarks
        self.selectedShopID = shops.first?.id
    }

    var filteredShops: [MapShop] {
        shops.filter { shop in
            let categoryMatches = selectedCategory == .all || shop.category == selectedCategory.rawValue
            let ownerMatches: Bool
            switch ownerFilter {
            case .me: ownerMatches = shop.owner == .me
            case .friend: ownerMatches = shop.owner == .friend
            case .both: ownerMatches = true
            }
            return categoryMatches && ownerMatches
        }
    }

    var selectedShop: MapShop? {
        shops.first { $0.id == selectedShopID }
    }

    func selectShop(_ shop: MapShop) {
        selectedShopID = shop.id
    }
}

nonisolated enum MapMockData {
    static let shops: [MapShop] = [
        MapShop(name: "麺屋 はる", category: "ラーメン", rating: 4, repeatCount: 3, owner: .me, sharedWithFriend: true, relativePosition: CGPoint(x: 0.47, y: 0.36)),
        MapShop(name: "支那そば 景", category: "ラーメン", rating: 3.5, repeatCount: 1, owner: .me, sharedWithFriend: false, relativePosition: CGPoint(x: 0.22, y: 0.20)),
        MapShop(name: "中華食堂 龍", category: "中華", rating: 4.5, repeatCount: 5, owner: .me, sharedWithFriend: true, relativePosition: CGPoint(x: 0.68, y: 0.18)),
        MapShop(name: "洋食キッチン 青", category: "洋食", rating: 4, repeatCount: 2, owner: .friend, sharedWithFriend: false, relativePosition: CGPoint(x: 0.80, y: 0.46)),
        MapShop(name: "らーめん 直久", category: "ラーメン", rating: 3, repeatCount: 1, owner: .friend, sharedWithFriend: false, relativePosition: CGPoint(x: 0.32, y: 0.56)),
        MapShop(name: "喫茶 根津", category: "カフェ", rating: 4, repeatCount: 2, owner: .friend, sharedWithFriend: false, relativePosition: CGPoint(x: 0.64, y: 0.66)),
        MapShop(name: "麺や 竹", category: "ラーメン", rating: 4, repeatCount: 2, owner: .me, sharedWithFriend: false, relativePosition: CGPoint(x: 0.12, y: 0.62)),
    ]

    static let landmarks: [MapLandmark] = [
        MapLandmark(name: "千駄木駅", relativePosition: CGPoint(x: 0.24, y: 0.28)),
        MapLandmark(name: "谷中銀座", relativePosition: CGPoint(x: 0.16, y: 0.42)),
        MapLandmark(name: "上野公園", relativePosition: CGPoint(x: 0.85, y: 0.30)),
        MapLandmark(name: "根津駅", relativePosition: CGPoint(x: 0.24, y: 0.72)),
    ]
}
