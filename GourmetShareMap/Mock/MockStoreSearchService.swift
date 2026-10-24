//
//  MockStoreSearchService.swift
//  GourmetShareMap
//

import CoreLocation

// TODO: PR-05（PlacesClient を使った検索）がマージされたら、RecordViewModel の既定値を本実装に差し替える。
/// UI 確認用のダミー検索。渡された座標の周辺に固定の店舗を並べて返す。
struct MockStoreSearchService: StoreSearchService {
    var returnsEmpty = false

    func searchNearbyStores(around coordinate: CLLocationCoordinate2D) async throws -> [StoreCandidate] {
        try await Task.sleep(for: .milliseconds(600))
        guard !returnsEmpty else { return [] }

        let samples: [(name: String, category: String, offset: Double)] = [
            ("麺屋 はる", "ラーメン・麺類", 0.0004),
            ("中華 福来", "中華", 0.0009),
            ("喫茶 こもれび", "カフェ・喫茶", 0.0015),
            ("居酒屋 たぬき", "居酒屋・バー", 0.0022),
        ]
        return samples.enumerated().map { index, sample in
            StoreCandidate(
                googlePlaceId: "mock-place-\(index)",
                name: sample.name,
                category: sample.category,
                latitude: coordinate.latitude + sample.offset,
                longitude: coordinate.longitude + sample.offset / 2
            )
        }
    }
}
