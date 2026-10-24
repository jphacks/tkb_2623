//
//  MockStoreSearchService.swift
//  GourmetShareMap
//

import CoreLocation

/// プレビュー・テスト用のダミー検索。渡された座標の周辺に固定の店舗を並べて返す。
struct MockStoreSearchService: StoreSearchService {
    var returnsEmpty = false

    func searchNearbyStores(around coordinate: CLLocationCoordinate2D) async throws -> [NearbyShop] {
        try await Task.sleep(for: .milliseconds(600))
        guard !returnsEmpty else { return [] }

        let samples: [(name: String, category: String, offset: Double)] = [
            ("麺屋 はる", "ラーメン・麺類", 0.0004),
            ("中華 福来", "中華", 0.0009),
            ("喫茶 こもれび", "カフェ・喫茶", 0.0015),
            ("居酒屋 たぬき", "居酒屋・バー", 0.0022),
        ]
        return samples.enumerated().map { index, sample in
            NearbyShop(
                placeID: "mock-place-\(index)",
                name: sample.name,
                latitude: coordinate.latitude + sample.offset,
                longitude: coordinate.longitude + sample.offset / 2,
                category: sample.category
            )
        }
    }
}
