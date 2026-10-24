//
//  MapViewModel.swift
//  GourmetShareMap
//

import CoreLocation
import Foundation
import Observation

/// カテゴリ絞り込みの選択肢。`PlaceCategoryClassifier` の13分類に「すべて」を加えたもの。
enum StoreCategoryFilter: Identifiable, Hashable {
    case all
    case category(String)

    static let allFilters: [StoreCategoryFilter] =
        [.all] + PlaceCategoryClassifier.categoryNames.map(StoreCategoryFilter.category)

    var id: String { title }

    var title: String {
        switch self {
        case .all: "すべて"
        case let .category(name): name
        }
    }

    var symbolName: String {
        switch self {
        case .all: "line.3.horizontal.decrease"
        case let .category(name): StoreCategoryStyle.symbolName(for: name)
        }
    }

    /// 「すべて」以外が選ばれている=絞り込みが効いている状態。
    var isActive: Bool { self != .all }

    func matches(_ category: String) -> Bool {
        switch self {
        case .all: true
        case let .category(name): name == category
        }
    }
}

enum OwnerFilter: String, CaseIterable, Identifiable {
    case me = "自分"
    case friend = "フレンド"
    case both = "両方"

    var id: String { rawValue }
}

/// マップに表示する1店舗。`store` の1行に対応し、座標を持つ行のみを表す。
struct MapStore: Identifiable, Equatable {
    let id: UUID
    let name: String
    let category: String
    /// 未評価の記録では nil。
    let rating: Double?
    let repeatCount: Int
    let memo: String?
    /// 編集保存時に既存値を消さないよう保持する。保存は全項目の上書きのため。
    let googlePlaceID: String?
    let latitude: Double
    let longitude: Double
    /// 自分の記録か、フォロー中のフレンドの記録か。
    let isMine: Bool
    /// 同じGoogle店舗を自分とフレンドの両方が登録しており、ピンにフレンドアイコンを重ねるかどうか。
    let sharedWithFriend: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// マップの絞り込みと選択状態を持つ。
/// 店舗データ自体は`RecordStore`が一元管理するため、ここでは取得せず変換と絞り込みだけを行う。
@MainActor
@Observable
final class MapViewModel {
    var selectedCategory: StoreCategoryFilter = .all
    var ownerFilter: OwnerFilter = .both
    var selectedStoreID: MapStore.ID?

    /// `RecordStore` のキャッシュをピンとして置ける形へ変換する。
    /// 座標がNULLの行はマップに置けないため除外する。
    /// 同じ `google_place_id` を自分とフレンドの両方が登録している店舗には共有フラグを立てる。
    func stores(from visible: VisibleStores?) -> [MapStore] {
        guard let visible else { return [] }

        let ownPlaceIDs = Set(visible.stores.lazy
            .filter { $0.userID == visible.currentUserID }
            .compactMap(\.googlePlaceID))
        let friendPlaceIDs = Set(visible.stores.lazy
            .filter { $0.userID != visible.currentUserID }
            .compactMap(\.googlePlaceID))
        let sharedPlaceIDs = ownPlaceIDs.intersection(friendPlaceIDs)

        return visible.stores.compactMap { record in
            guard let latitude = record.latitude, let longitude = record.longitude else { return nil }
            return MapStore(
                id: record.id,
                name: record.name,
                category: record.category ?? "その他",
                rating: record.reputation,
                repeatCount: record.repeatNum,
                memo: record.memo,
                googlePlaceID: record.googlePlaceID,
                latitude: latitude,
                longitude: longitude,
                isMine: record.userID == visible.currentUserID,
                sharedWithFriend: record.googlePlaceID.map(sharedPlaceIDs.contains) ?? false
            )
        }
    }

    func filtered(_ stores: [MapStore]) -> [MapStore] {
        stores.filter { store in
            guard selectedCategory.matches(store.category) else { return false }
            switch ownerFilter {
            case .me: return store.isMine
            case .friend: return !store.isMine
            case .both: return true
            }
        }
    }

    func selectedStore(in stores: [MapStore]) -> MapStore? {
        guard let selectedStoreID else { return nil }
        return stores.first { $0.id == selectedStoreID }
    }

    func select(storeID: MapStore.ID?) {
        selectedStoreID = storeID
    }
}
