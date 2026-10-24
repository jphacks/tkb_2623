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
}

/// 学習済みモデルの状態。
struct ModelStats: Equatable, Sendable {
    /// モデルの学習に使われた記録の件数。
    let trainedRecordCount: Int
    /// 5-Fold交差検証のMAE（★いくつぶんズレるか）。APIがまだ返さないあいだは nil。
    let meanAbsoluteError: Double?

    /// MAEを「好みの読み当て率」(0〜100)に直した値。評価は1〜5の5段階＝最大4のズレなので、
    /// `1 - MAE / 4` を百分率にしている。MAEが無ければ nil。
    var accuracyPercent: Int? {
        guard let mae = meanAbsoluteError else { return nil }
        return Int((max(0, 1 - mae / 4) * 100).rounded())
    }
}

/// レコメンドとモデル情報の取得。
/// 本番の実装は別リポジトリの推論API（`POST /predict`・`POST /train`）を叩く予定で、
/// それが決まるまでは `MockRecommendService` を使う。
protocol RecommendServing: Sendable {
    /// 学習済みモデルの状態。`records` は、APIが無いあいだモックが件数から仮の精度を作るために渡している。
    func fetchModelStats(records: [StoreRecord]) async throws -> ModelStats
    /// 自分の記録を履歴として渡し、おすすめ1件を受け取る。
    func recommend(from records: [StoreRecord]) async throws -> Recommendation
}

enum RecommendError: LocalizedError, Equatable {
    case notEnoughRecords

    var errorDescription: String? {
        switch self {
        case .notEnoughRecords: return "まずはお店を1件登録してください。"
        }
    }
}

/// APIが繋がるまでの仮実装。自分の記録の内容から、それらしいおすすめと精度を組み立てる。
// TODO: 別リポジトリの推論APIが決まったら、URLSessionで叩く実装に差し替える。
//       `GET /health`・`POST /predict` を想定していて、差し替えはこのファイルだけで済む。
struct MockRecommendService: RecommendServing {
    /// APIの往復に見えるだけの待ち時間。
    var delay: Duration = .milliseconds(700)

    func fetchModelStats(records: [StoreRecord]) async throws -> ModelStats {
        try await Task.sleep(for: delay)
        // 記録が増えるほどズレが小さくなる仮の値。実APIは5-Foldの評価値を返す想定。
        let mae = max(0.35, 1.2 - Double(records.count) * 0.03)
        return ModelStats(trainedRecordCount: records.count, meanAbsoluteError: mae)
    }

    func recommend(from records: [StoreRecord]) async throws -> Recommendation {
        guard !records.isEmpty else { throw RecommendError.notEnoughRecords }
        try await Task.sleep(for: delay)

        let category = Self.favoriteCategory(in: records)
        let rated = records.compactMap(\.reputation)
        let average = rated.isEmpty ? 3.5 : rated.reduce(0, +) / Double(rated.count)
        let matching = records.filter { $0.category == category }.count
        let predicted = min(5, max(1, average + 0.4))

        return Recommendation(
            placeID: "mock-place-\(category)",
            name: Self.sampleName(for: category),
            category: category,
            predictedRating: (predicted * 10).rounded() / 10,
            reason: "\(category)の記録が\(matching)件あって、平均★\(String(format: "%.1f", average))。似た雰囲気のお店です。"
        )
    }

    /// 一番多く記録しているジャンル。記録が無ければ「ラーメン」。
    private static func favoriteCategory(in records: [StoreRecord]) -> String {
        let counts = Dictionary(grouping: records.compactMap(\.category), by: { $0 }).mapValues(\.count)
        // 件数が同じときに表示が入れ替わらないよう、名前順で決める。
        return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? "ラーメン"
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
