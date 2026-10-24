import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Nearby Searchで取得した店舗。緯度・経度は検索位置ではなく店舗の位置。
struct NearbyShop: Equatable, Sendable {
    let placeID: String
    let name: String
    let latitude: Double
    let longitude: Double
    let category: String
}

enum NearbyShopError: LocalizedError {
    case invalidCoordinate
    case missingAPIKey
    case invalidResponse
    case api(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidCoordinate:
            return "緯度は-90〜90、経度は-180〜180の有限な数値で指定してください。"
        case .missingAPIKey:
            return "GoogleMapConfig.swift の apiKey に実際のAPIキーを設定してください。"
        case .invalidResponse:
            return "店舗情報のレスポンスが不正です。"
        case let .api(statusCode, message):
            return "Places APIエラー (HTTP \(statusCode)): \(message)"
        }
    }
}

/// 指定位置の半径1km以内から飲食店（restaurant / cafe）を距離順に最大5件返す。
/// 該当店舗がなければ空配列。設定・通信・API・デコードエラーはthrowする。
func findNearestShop(latitude: Double, longitude: Double) async throws -> [NearbyShop] {
    try await NearbyShopClient.findNearestShop(
        latitude: latitude,
        longitude: longitude,
        apiKey: GoogleMapConfig.apiKey,
        session: .shared
    )
}

// 通信先のセッションを差し替えて、実APIを呼ばずに検証できるようにする。
enum NearbyShopClient {
    static func findNearestShop(
        latitude: Double,
        longitude: Double,
        apiKey: String,
        session: URLSession
    ) async throws -> [NearbyShop] {
        guard latitude.isFinite, (-90...90).contains(latitude),
              longitude.isFinite, (-180...180).contains(longitude) else {
            throw NearbyShopError.invalidCoordinate
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key != "YOUR_GOOGLE_MAPS_API_KEY" else {
            throw NearbyShopError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchNearby")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("places.id,places.displayName,places.location,places.primaryType,places.types",
                         forHTTPHeaderField: "X-Goog-FieldMask")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "languageCode": "ja",
            "includedTypes": ["restaurant", "cafe"],
            "maxResultCount": 5,
            "rankPreference": "DISTANCE",
            "locationRestriction": ["circle": [
                "center": ["latitude": latitude, "longitude": longitude],
                "radius": 1000.0,
            ]],
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NearbyShopError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(decoding: data, as: UTF8.self)
                .replacingOccurrences(of: key, with: "[REDACTED]")
            throw NearbyShopError.api(statusCode: http.statusCode, message: message)
        }
        let result = try JSONDecoder().decode(SearchResponse.self, from: data)
        return try (result.places ?? []).prefix(5).map { place in
            guard !place.id.isEmpty, !place.displayName.text.isEmpty,
                  place.location.latitude.isFinite, (-90...90).contains(place.location.latitude),
                  place.location.longitude.isFinite, (-180...180).contains(place.location.longitude) else {
                throw NearbyShopError.invalidResponse
            }
            return NearbyShop(
                placeID: place.id,
                name: place.displayName.text,
                latitude: place.location.latitude,
                longitude: place.location.longitude,
                category: PlaceCategoryClassifier.category(primaryType: place.primaryType, types: place.types ?? [])
            )
        }
    }

    private struct SearchResponse: Decodable {
        let places: [Place]?
    }

    private struct Place: Decodable {
        let id: String
        let displayName: DisplayName
        let location: Location
        let primaryType: String?
        let types: [String]?
    }

    private struct DisplayName: Decodable {
        let text: String
    }

    private struct Location: Decodable {
        let latitude: Double
        let longitude: Double
    }
}
