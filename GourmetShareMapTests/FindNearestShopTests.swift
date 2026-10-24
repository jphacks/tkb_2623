import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import GourmetShareMap

// URLProtocolの共有ハンドラを使うため、このスイート内は直列実行する。
@Suite(.serialized)
struct FindNearestShopTests {
    private let validLatitude = 35.681236
    private let validLongitude = 139.767125
    private let validAPIKey = "test-api-key"

    @Test func outOfRangeOrNonFiniteCoordinatesThrowWithoutSendingRequest() async throws {
        NearestShopMockURLProtocol.reset { _ in (200, Data()) }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let cases: [(Double, Double)] = [
            (-90.1, 0), (90.1, 0), (0, -180.1), (0, 180.1),
            (.nan, 0), (.infinity, 0), (0, -.infinity),
        ]
        for (latitude, longitude) in cases {
            do {
                _ = try await NearbyShopClient.findNearestShop(
                    latitude: latitude, longitude: longitude, apiKey: validAPIKey, session: session
                )
                Issue.record("invalidCoordinateがthrowされませんでした: (\(latitude), \(longitude))")
            } catch NearbyShopError.invalidCoordinate {
                // 期待通り
            } catch {
                Issue.record("予期しないエラー: \(error)")
            }
        }
        #expect(NearestShopMockURLProtocol.requests.isEmpty)
    }

    @Test func missingOrPlaceholderAPIKeyThrowsWithoutSendingRequest() async throws {
        NearestShopMockURLProtocol.reset { _ in (200, Data()) }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        for key in ["", "   \n", "YOUR_GOOGLE_MAPS_API_KEY", " YOUR_GOOGLE_MAPS_API_KEY \n"] {
            do {
                _ = try await NearbyShopClient.findNearestShop(
                    latitude: validLatitude, longitude: validLongitude, apiKey: key, session: session
                )
                Issue.record("missingAPIKeyがthrowされませんでした: \"\(key)\"")
            } catch NearbyShopError.missingAPIKey {
                // 期待通り
            } catch {
                Issue.record("予期しないエラー: \(error)")
            }
        }
        #expect(NearestShopMockURLProtocol.requests.isEmpty)
    }

    @Test func httpErrorStatusThrowsApiErrorWithRedactedKeyInMessage() async throws {
        let body = Data("{\"error\":{\"message\":\"API key \(validAPIKey) is invalid\"}}".utf8)
        NearestShopMockURLProtocol.reset { _ in (403, body) }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        do {
            _ = try await NearbyShopClient.findNearestShop(
                latitude: validLatitude, longitude: validLongitude, apiKey: validAPIKey, session: session
            )
            Issue.record("APIエラーがthrowされませんでした")
        } catch NearbyShopError.api(let statusCode, let message) {
            #expect(statusCode == 403)
            #expect(!message.contains(validAPIKey))
            #expect(message.contains("[REDACTED]"))
        } catch {
            Issue.record("予期しないエラー: \(error)")
        }
    }

    @Test func malformedPlaceFieldsThrowInvalidResponse() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let cases = [
            singlePlaceJSON(id: "", name: "店", latitude: 35, longitude: 139),
            singlePlaceJSON(id: "p1", name: "", latitude: 35, longitude: 139),
            singlePlaceJSON(id: "p1", name: "店", latitude: 91, longitude: 139),
            singlePlaceJSON(id: "p1", name: "店", latitude: 35, longitude: 181),
        ]
        for json in cases {
            NearestShopMockURLProtocol.reset { _ in (200, Data(json.utf8)) }
            do {
                _ = try await NearbyShopClient.findNearestShop(
                    latitude: validLatitude, longitude: validLongitude, apiKey: validAPIKey, session: session
                )
                Issue.record("invalidResponseがthrowされませんでした: \(json)")
            } catch NearbyShopError.invalidResponse {
                // 期待通り
            } catch {
                Issue.record("予期しないエラー: \(error)")
            }
        }
    }

    @Test func emptyPlacesResponseReturnsEmptyArray() async throws {
        NearestShopMockURLProtocol.reset { _ in (200, Data(#"{"places":[]}"#.utf8)) }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let shops = try await NearbyShopClient.findNearestShop(
            latitude: validLatitude, longitude: validLongitude, apiKey: validAPIKey, session: session
        )
        #expect(shops.isEmpty)
    }

    @Test func successfulResponseIsLimitedToFiveResultsPreservingDistanceOrderAndCategory() async throws {
        // APIがrankPreference: DISTANCEで既に距離順に返す前提。6件返っても先頭5件に絞られることを検証する。
        let places = (1...6).map { index in
            placeFragment(
                id: "place-\(index)", name: "店舗\(index)",
                latitude: 35.0 + Double(index) * 0.001, longitude: 139.0,
                primaryType: index == 1 ? "ramen_restaurant" : nil,
                types: index == 1 ? ["ramen_restaurant"] : ["cafe"]
            )
        }
        let json = "{\"places\":[\(places.joined(separator: ","))]}"
        NearestShopMockURLProtocol.reset { _ in (200, Data(json.utf8)) }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let shops = try await NearbyShopClient.findNearestShop(
            latitude: validLatitude, longitude: validLongitude, apiKey: validAPIKey, session: session
        )
        #expect(shops.count == 5)
        #expect(shops.map(\.placeID) == ["place-1", "place-2", "place-3", "place-4", "place-5"])
        #expect(shops.first?.name == "店舗1")
        #expect(shops.first?.category == "ラーメン・麺類")
        #expect(shops.last?.category == "カフェ・喫茶")

        let request = try #require(NearestShopMockURLProtocol.requests.last)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://places.googleapis.com/v1/places:searchNearby")
        #expect(request.value(forHTTPHeaderField: "X-Goog-Api-Key") == validAPIKey)
        #expect(request.value(forHTTPHeaderField: "X-Goog-FieldMask")
                == "places.id,places.displayName,places.location,places.primaryType,places.types")
        let requestBodyJSON = try requestBody(request)
        #expect(requestBodyJSON["languageCode"] as? String == "ja")
        #expect(requestBodyJSON["includedTypes"] as? [String] == ["restaurant", "cafe"])
        #expect(requestBodyJSON["maxResultCount"] as? Int == 5)
        #expect(requestBodyJSON["rankPreference"] as? String == "DISTANCE")
        let restriction = try #require(requestBodyJSON["locationRestriction"] as? [String: Any])
        let circle = try #require(restriction["circle"] as? [String: Any])
        #expect(circle["radius"] as? Double == 1000.0)
        let center = try #require(circle["center"] as? [String: Any])
        #expect(center["latitude"] as? Double == validLatitude)
        #expect(center["longitude"] as? Double == validLongitude)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NearestShopMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func singlePlaceJSON(id: String, name: String, latitude: Double, longitude: Double) -> String {
        let fragment = placeFragment(
            id: id, name: name, latitude: latitude, longitude: longitude, primaryType: nil, types: nil
        )
        return "{\"places\":[\(fragment)]}"
    }

    private func placeFragment(
        id: String, name: String, latitude: Double, longitude: Double,
        primaryType: String?, types: [String]?
    ) -> String {
        var fields = [
            "\"id\":\"\(id)\"",
            "\"displayName\":{\"text\":\"\(name)\"}",
            "\"location\":{\"latitude\":\(latitude),\"longitude\":\(longitude)}",
        ]
        if let primaryType { fields.append("\"primaryType\":\"\(primaryType)\"") }
        if let types { fields.append("\"types\":[\(types.map { "\"\($0)\"" }.joined(separator: ","))]") }
        return "{\(fields.joined(separator: ","))}"
    }

    private func requestBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class NearestShopMockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    // 全アクセスをlockで保護する。URLProtocolのコールバックは別スレッドで実行される。
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) private static var recordedRequests: [URLRequest] = []

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recordedRequests
    }

    static func reset(handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler
        recordedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            // URLSessionがHTTPBodyをストリームへ変換する場合も送信内容を記録する。
            var captured = request
            if captured.httpBody == nil, let stream = captured.httpBodyStream {
                stream.open(); defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
                    if count == 0 { break }
                    data.append(buffer, count: count)
                }
                captured.httpBody = data
            }
            Self.lock.lock()
            let handler = Self.handler
            Self.recordedRequests.append(captured)
            Self.lock.unlock()
            guard let handler else { throw URLError(.unsupportedURL) }
            let (status, data) = try handler(captured)
            let response = HTTPURLResponse(url: captured.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
