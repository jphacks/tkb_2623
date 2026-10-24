import Foundation

nonisolated struct RecommendationInput: Encodable, Sendable {
    let genre: String
    let latitude: Double
    let longitude: Double
    var area: String? = nil
    var preferences: RecommendationPreferences? = nil
}

/// Attributes extracted from an image by the caller. Missing attributes stay nil/empty.
nonisolated struct RecommendationPreferences: Encodable, Equatable, Sendable {
    var taste: String? = nil
    var atmosphere: String? = nil
    var ingredients: [String] = []
}

nonisolated struct RecommendedShop: Decodable, Equatable, Sendable {
    let placeID: String
    let name: String
    let latitude: Double
    let longitude: Double

    enum CodingKeys: String, CodingKey {
        case placeID = "place_id"
        case name, latitude, longitude
    }
}

/// Display the attributions alongside the recommendation when adding a UI.
nonisolated struct RecommendationAttribution: Decodable, Equatable, Sendable {
    let provider: String
    let name: String
    let url: URL
}

nonisolated struct RecommendationResult: Decodable, Equatable, Sendable {
    let recommendation: RecommendedShop
    let attributions: [RecommendationAttribution]
}

nonisolated struct RecommendationAreaCandidate: Decodable, Equatable, Sendable {
    let name: String
    let address: String
}

nonisolated struct RecommendationAPIError: Decodable, Equatable, Sendable {
    let code: String
    let message: String
    let candidates: [RecommendationAreaCandidate]?
}

nonisolated enum RecommendationError: LocalizedError, Equatable, Sendable {
    case invalidInput
    case api(statusCode: Int, error: RecommendationAPIError)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidInput: "ジャンル・座標・検索地名・嗜好の属性を確認してください。"
        case let .api(_, error): error.message
        case .invalidResponse: "推薦APIから有効な応答を取得できませんでした。"
        }
    }
}
