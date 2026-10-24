//
//  MapViewModel.swift
//  GourmetShareMap
//

import Combine
import CoreLocation
import Foundation

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

@MainActor
final class MapViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published var selectedCategory: StoreCategoryFilter = .all
    @Published var ownerFilter: OwnerFilter = .both
    @Published var selectedStoreID: MapStore.ID?
    @Published private(set) var stores: [MapStore] = []
    @Published private(set) var loadState: LoadState = .idle

    private let repository: RecordRepository

    // RecordRepositoryは@MainActorのため、既定値の式を呼び出し側(非分離)では評価できない。
    // nilを受け取ってinit内で生成する。
    init(repository: RecordRepository? = nil) {
        self.repository = repository ?? RecordRepository()
    }

    /// 自分とフォロー中フレンドの店舗記録を読み込む。
    /// 失敗しても例外は投げず、画面に出すメッセージとして `loadState` に保持する。
    func load() async {
        loadState = .loading
        do {
            let visible = try await repository.fetchVisibleStores()
            stores = Self.mapStores(from: visible)
            // 表示対象から外れたピンの選択が残らないようにする。
            if let selectedStoreID, !stores.contains(where: { $0.id == selectedStoreID }) {
                self.selectedStoreID = nil
            }
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    var filteredStores: [MapStore] {
        stores.filter { store in
            guard selectedCategory.matches(store.category) else { return false }
            switch ownerFilter {
            case .me: return store.isMine
            case .friend: return !store.isMine
            case .both: return true
            }
        }
    }

    var selectedStore: MapStore? {
        guard let selectedStoreID else { return nil }
        return stores.first { $0.id == selectedStoreID }
    }

    func select(storeID: MapStore.ID?) {
        selectedStoreID = storeID
    }

    /// 座標がNULLの行はマップに置けないため除外する。
    /// 同じ `google_place_id` を自分とフレンドの両方が登録している店舗には共有フラグを立てる。
    private static func mapStores(from visible: VisibleStores) -> [MapStore] {
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
}
