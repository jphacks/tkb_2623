import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Supabase
import Testing
@testable import GourmetShareMap

@Suite(.serialized)
@MainActor
struct RecommendationRepositoryTests {
    private let success = Data("""
    {"recommendation":{"place_id":"verified-place","name":"推薦店舗","latitude":35,"longitude":139},
    "attributions":[{"provider":"Google Maps","name":"推薦店舗","url":"https://maps.google.com/?cid=123"}]}
    """.utf8)

    @Test func encodesInputAndSessionJWTAndDecodesVerifiedResultWithAttribution() async throws {
        let (repository, session) = try await makeRepository()
        defer { session.invalidateAndCancel() }
        let result = try await repository.recommend(.init(genre: " ラーメン ", latitude: 35, longitude: 139, area: " 渋谷駅 "))
        #expect(result.recommendation.placeID == "verified-place")
        #expect(result.recommendation.name == "推薦店舗")
        #expect(result.recommendation.latitude == 35)
        #expect(result.recommendation.longitude == 139)
        #expect(result.attributions.first?.provider == "Google Maps")
        #expect(result.attributions.first?.url.absoluteString == "https://maps.google.com/?cid=123")
        let request = try #require(RecommendationMockURLProtocol.requests.last)
        #expect(request.url?.path == "/functions/v1/recommend-shop")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer recommendation-access-token")
        #expect(request.value(forHTTPHeaderField: "apikey") == "recommendation-anon-key")
        #expect(request.timeoutInterval == 65)
        let body = try requestBody(request)
        #expect(body["genre"] as? String == "ラーメン")
        #expect(body["latitude"] as? Double == 35)
        #expect(body["longitude"] as? Double == 139)
        #expect(body["area"] as? String == "渋谷駅")
        #expect(body["user_id"] == nil)
        #expect(body["reason"] == nil)
    }

    @Test func omitsAbsentOrBlankArea() async throws {
        let (repository, session) = try await makeRepository()
        defer { session.invalidateAndCancel() }
        for area: String? in [nil, " \n "] {
            _ = try await repository.recommend(.init(genre: "カフェ", latitude: 35, longitude: 139, area: area))
            let request = try #require(RecommendationMockURLProtocol.requests.last)
            #expect(try requestBody(request)["area"] == nil)
        }
    }

    @Test func invalidInputsDoNotSendRequests() async throws {
        let (repository, session) = try await makeRepository()
        defer { session.invalidateAndCancel() }
        let inputs: [RecommendationInput] = [
            .init(genre: " \n ", latitude: 35, longitude: 139),
            .init(genre: String(repeating: "a", count: 201), latitude: 35, longitude: 139),
            .init(genre: "x", latitude: .nan, longitude: 139),
            .init(genre: "x", latitude: .infinity, longitude: 139),
            .init(genre: "x", latitude: 91, longitude: 139),
            .init(genre: "x", latitude: 35, longitude: -181),
            .init(genre: "x", latitude: 35, longitude: 139, area: String(repeating: "a", count: 201)),
        ]
        for input in inputs {
            await #expect(throws: RecommendationError.invalidInput) { try await repository.recommend(input) }
        }
        #expect(RecommendationMockURLProtocol.requests.isEmpty)
    }

    @Test func signedOutDoesNotCallFunction() async throws {
        let (repository, session) = try await makeRepository(signedIn: false)
        defer { session.invalidateAndCancel() }
        await #expect(throws: (any Error).self) {
            try await repository.recommend(.init(genre: "カフェ", latitude: 35, longitude: 139))
        }
        #expect(RecommendationMockURLProtocol.requests.isEmpty)
    }

    @Test(arguments: [400, 401, 404, 422, 500, 502, 504])
    func propagatesServerStatusCodeMessageAndAreaCandidates(status: Int) async throws {
        let data = Data("""
        {"error":{"code":"TEST_ERROR","message":"検索できませんでした。",
        "candidates":[{"name":"駅名","address":"東京都"}]}}
        """.utf8)
        let (repository, session) = try await makeRepository(status: status, response: data)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await repository.recommend(.init(genre: "カフェ", latitude: 35, longitude: 139))
            Issue.record("Expected server error")
        } catch let RecommendationError.api(statusCode, error) {
            #expect(statusCode == status)
            #expect(error.code == "TEST_ERROR")
            #expect(error.message == "検索できませんでした。")
            #expect(error.candidates == [.init(name: "駅名", address: "東京都")])
        }
        #expect(RecommendationMockURLProtocol.requests.count == 1)
    }

    @Test func rejectsMalformedSuccessAndMalformedErrorWithoutReturningRawData() async throws {
        for status in [200, 502] {
            let (repository, session) = try await makeRepository(status: status, response: Data("private raw response".utf8))
            defer { session.invalidateAndCancel() }
            await #expect(throws: RecommendationError.invalidResponse) {
                try await repository.recommend(.init(genre: "カフェ", latitude: 35, longitude: 139))
            }
        }
    }

    @Test func rejectsUnusableShopOrAttribution() async throws {
        for (original, replacement) in [
            ("verified-place", ""), ("\"latitude\":35", "\"latitude\":91"),
            ("https://maps.google.com/?cid=123", "http://maps.google.com/?cid=123"),
            ("\"provider\":\"Google Maps\"", "\"provider\":\"\""),
        ] {
            let data = Data(String(decoding: success, as: UTF8.self).replacingOccurrences(of: original, with: replacement).utf8)
            let (repository, session) = try await makeRepository(response: data)
            defer { session.invalidateAndCancel() }
            await #expect(throws: RecommendationError.invalidResponse) {
                try await repository.recommend(.init(genre: "カフェ", latitude: 35, longitude: 139))
            }
        }
    }

    @Test func transportErrorPropagatesWithoutRetry() async throws {
        let (repository, session) = try await makeRepository(networkError: true)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await repository.recommend(.init(genre: "カフェ", latitude: 35, longitude: 139))
            Issue.record("Expected transport error")
        } catch let error as URLError {
            #expect(error.code == .notConnectedToInternet)
        }
        #expect(RecommendationMockURLProtocol.requests.count == 1)
    }

    private func makeRepository(
        signedIn: Bool = true, status: Int = 200, response: Data? = nil, networkError: Bool = false
    ) async throws -> (RecommendationRepository, URLSession) {
        let result = response ?? success
        let expiry = Int(Date().timeIntervalSince1970) + 3600
        let auth = Data("""
        {"access_token":"recommendation-access-token","token_type":"bearer","refresh_token":"test-refresh",
        "expires_in":3600,"expires_at":\(expiry),"user":{"id":"11111111-1111-1111-1111-111111111111",
        "aud":"authenticated","role":"authenticated","app_metadata":{},"user_metadata":{},
        "created_at":"2025-10-24T12:00:00Z","updated_at":"2025-10-24T12:00:00Z","is_anonymous":false}}
        """.utf8)
        RecommendationMockURLProtocol.reset { request in
            if request.url?.path == "/auth/v1/token" { return (200, auth) }
            guard request.url?.path == "/functions/v1/recommend-shop" else { throw URLError(.unsupportedURL) }
            if networkError { throw URLError(.notConnectedToInternet) }
            return (status, result)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecommendationMockURLProtocol.self]
        let session = URLSession(configuration: config)
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://recommendation-tests.invalid")!, supabaseKey: "recommendation-anon-key",
            options: .init(auth: .init(storage: RecommendationTestAuthStorage(), autoRefreshToken: false),
                           global: .init(session: session))
        )
        if signedIn { _ = try await client.auth.signIn(email: "test@example.com", password: "test-password") }
        return (RecommendationRepository(client: client), session)
    }

    private func requestBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class RecommendationTestAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws {
        lock.lock(); defer { lock.unlock() }; values[key] = value
    }
    func retrieve(key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }; return values[key]
    }
    func remove(key: String) throws {
        lock.lock(); defer { lock.unlock() }; values[key] = nil
    }
}

private final class RecommendationMockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) private static var recordedRequests: [URLRequest] = []
    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }; return recordedRequests
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
            if captured.url?.path == "/functions/v1/recommend-shop" { Self.recordedRequests.append(captured) }
            Self.lock.unlock()
            guard let handler else { throw URLError(.unsupportedURL) }
            let (status, data) = try handler(captured)
            let response = HTTPURLResponse(url: captured.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
