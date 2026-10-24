//
//  StoreCandidate.swift
//  GourmetShareMap
//

import CoreLocation

/// 周辺店舗検索で返ってくる候補 1 件分。
struct StoreCandidate: Identifiable, Hashable, Sendable {
    let googlePlaceId: String
    let name: String
    /// PR-03 のカテゴリ分類結果（例: "ラーメン・麺類"）。分類できなければ nil。
    let category: String?
    let latitude: Double
    let longitude: Double

    var id: String { googlePlaceId }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// 候補リストで店舗アイコンとして使う SF Symbol。
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
