//
//  RecommendService.swift
//  GourmetShareMap
//

import Foundation

/// AIが薦めたお店1件。
struct Recommendation: Identifiable, Equatable, Sendable {
    let placeID: String
    let name: String
    let category: String
    /// モデルが予測したこの人の評価（1〜5）。
    let predictedRating: Double
    /// 「ラーメンの記録が8件あって平均★4.3」のような、薦めた理由。
    let reason: String

    var id: String { placeID }

    /// Google Mapsでこの店を開くURL。`query_place_id`を指定しているので、
    /// 同名の別店舗と混同されず常にこの店舗が開く。
    /// https://developers.google.com/maps/documentation/urls/get-started
    var mapsURL: URL? {
        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: name),
            URLQueryItem(name: "query_place_id", value: placeID),
        ]
        return components?.url
    }
}

/// 学習済みモデルの状態。
struct ModelStats: Equatable, Sendable {
    /// モデルの学習に使われた記録の件数。
    let trainedRecordCount: Int
    /// LOOCV（1件抜き交差検証）のMAE（★いくつぶんズレるか）。未学習・未取得のあいだは nil。
    let meanAbsoluteError: Double?

    /// MAEを「好みの読み当て率」(0〜100)に直した値。評価は1〜5の5段階＝最大4のズレなので、
    /// `1 - MAE / 4` を百分率にしている。MAEが無ければ nil。
    var accuracyPercent: Int? {
        guard let mae = meanAbsoluteError else { return nil }
        return Int((max(0, 1 - mae / 4) * 100).rounded())
    }
}

/// レコメンドとモデル情報の取得。
/// 本番の実装(`LiveRecommendService`)はSupabaseの`ai-recommend` Edge Function経由で
/// Cloud Run上のAIバックエンド（ユーザーごとのLightGBMモデル）を呼ぶ。
protocol RecommendServing: Sendable {
    /// 学習済みモデルの状態。`records` は、APIの結果が無いあいだモックが件数から仮の精度を作るために渡している。
    func fetchModelStats(records: [StoreRecord]) async throws -> ModelStats
    /// フリーテキスト（「ラーメン食べたい」等）と現在地から、おすすめ上位3件を受け取る。
    /// `records` は学習データ件数のチェック（未登録なら `notEnoughRecords`）に使う。
    func recommend(freeText: String, latitude: Double, longitude: Double, records: [StoreRecord]) async throws -> [Recommendation]
}

enum RecommendError: LocalizedError, Equatable {
    case notEnoughRecords

    var errorDescription: String? {
        switch self {
        case .notEnoughRecords: return "まずはお店を5件登録してください。"
        }
    }
}

/// APIが繋がるまでの仮実装。自分の記録の内容から、それらしいおすすめと精度を組み立てる。
struct MockRecommendService: RecommendServing {
    /// APIの往復に見えるだけの待ち時間。
    var delay: Duration = .milliseconds(700)

    func fetchModelStats(records: [StoreRecord]) async throws -> ModelStats {
        try await Task.sleep(for: delay)
        // 記録が増えるほどズレが小さくなる仮の値。実APIはLOOCVの評価値を返す。
        let mae = max(0.35, 1.2 - Double(records.count) * 0.03)
        return ModelStats(trainedRecordCount: records.count, meanAbsoluteError: mae)
    }

    func recommend(freeText: String, latitude: Double, longitude: Double, records: [StoreRecord]) async throws -> [Recommendation] {
        guard !records.isEmpty else { throw RecommendError.notEnoughRecords }
        try await Task.sleep(for: delay)

        let categories = Self.topCategories(in: records, limit: 3)
        let rated = records.compactMap(\.reputation)
        let average = rated.isEmpty ? 3.5 : rated.reduce(0, +) / Double(rated.count)

        return categories.enumerated().map { index, category in
            let matching = records.filter { $0.category == category }.count
            let predicted = min(5, max(1, average + 0.4 - Double(index) * 0.15))
            return Recommendation(
                placeID: "mock-place-\(category)",
                name: Self.sampleName(for: category),
                category: category,
                predictedRating: (predicted * 10).rounded() / 10,
                reason: "「\(freeText)」に近い、\(category)の記録が\(matching)件あって平均★\(String(format: "%.1f", average))。"
            )
        }
    }

    /// 多く記録しているジャンルの上位（同数は名前順）。記録が無ければ「ラーメン・麺類」。
    private static func topCategories(in records: [StoreRecord], limit: Int) -> [String] {
        let counts = Dictionary(grouping: records.compactMap(\.category), by: { $0 }).mapValues(\.count)
        guard !counts.isEmpty else { return ["ラーメン・麺類"] }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(limit).map(\.key)
    }

    private static func sampleName(for category: String) -> String {
        switch category {
        case let name where name.hasPrefix("ラーメン"): "中華そば 一会"
        case let name where name.hasPrefix("カフェ"): "喫茶 ひので"
        case let name where name.hasPrefix("洋食"): "キッチン まるみ"
        case "中華": "大衆中華 福来"
        case "和食": "小料理 なぎさ"
        default: "食堂 こみち"
        }
    }
}
