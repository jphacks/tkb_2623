import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Place Details (New) で取得する、AIバックエンドの学習特徴量に使う3項目。
/// いずれもGoogle側が持っていなければnil（新規開店直後の店舗など）。
struct PlaceDetails: Equatable, Sendable {
    /// Googleの公開平均★（0〜5）。本人の評価（`StoreRecord.reputation`）とは別物。
    let rating: Double?
    /// 1(安い)〜4(高い)。Googleの価格帯が無ければnil。
    let priceLevel: Int?
    let userRatingCount: Int?
}

enum PlaceDetailsError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case api(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "GoogleMapsConfig.swift の apiKey に実際のAPIキーを設定してください。"
        case .invalidResponse:
            return "店舗詳細のレスポンスが不正です。"
        case let .api(statusCode, message):
            return "Places APIエラー (HTTP \(statusCode)): \(message)"
        }
    }
}

/// 指定したGoogle店舗IDの詳細（評価・価格帯・レビュー件数）を取得する。
/// 店舗登録時にAIバックエンドの学習用スナップショットとして保存する（`store.google_rating`等）。
/// 失敗しても記録そのものの保存は妨げたくないため、呼び出し側はbest-effortで扱うこと。
func findPlaceDetails(placeID: String) async throws -> PlaceDetails {
    try await PlaceDetailsClient.findPlaceDetails(placeID: placeID, apiKey: GoogleMapsConfig.apiKey, session: .shared)
}

enum PlaceDetailsClient {
    static func findPlaceDetails(placeID: String, apiKey: String, session: URLSession) async throws -> PlaceDetails {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key != "YOUR_GOOGLE_MAPS_API_KEY" else {
            throw PlaceDetailsError.missingAPIKey
        }
        let encodedID = placeID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? placeID
        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places/\(encodedID)")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("rating,priceLevel,userRatingCount", forHTTPHeaderField: "X-Goog-FieldMask")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PlaceDetailsError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(decoding: data, as: UTF8.self)
                .replacingOccurrences(of: key, with: "[REDACTED]")
            throw PlaceDetailsError.api(statusCode: http.statusCode, message: message)
        }
        let place = try JSONDecoder().decode(Place.self, from: data)
        return PlaceDetails(
            rating: place.rating,
            priceLevel: priceLevel(from: place.priceLevel),
            userRatingCount: place.userRatingCount
        )
    }

    private static func priceLevel(from rawValue: String?) -> Int? {
        switch rawValue {
        case "PRICE_LEVEL_FREE", "PRICE_LEVEL_INEXPENSIVE": 1
        case "PRICE_LEVEL_MODERATE": 2
        case "PRICE_LEVEL_EXPENSIVE": 3
        case "PRICE_LEVEL_VERY_EXPENSIVE": 4
        default: nil
        }
    }

    private struct Place: Decodable {
        let rating: Double?
        let priceLevel: String?
        let userRatingCount: Int?
    }
}
