import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Supabase
import Testing
@testable import GourmetShareMap

// URLProtocolの共有ハンドラを使うため、このスイート内は直列実行する。
@Suite(.serialized)
@MainActor
struct RecordRepositoryTests {
    private let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let storeID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    @Test func newGoogleStoreIsLookedUpThenInsertedAndDecodesAllFields() async throws {
        let (repository, session) = try await makeRepository()
        defer { session.invalidateAndCancel() }
        let saved = try await repository.saveStore(input())
        #expect(saved.id == storeID)
        #expect(saved.userID == userID)
        #expect(saved.name == "喫茶テスト")
        #expect(saved.category == "カフェ・喫茶")
        #expect(saved.reputation == 4)
        #expect(saved.googlePlaceID == "place-123")
        #expect(saved.memo == "また行きたい")
        #expect(saved.repeatNum == 2)
        #expect(saved.latitude == 35.0)
        #expect(saved.longitude == 139.0)
        #expect(abs(saved.createdAt.timeIntervalSince1970 - 1_761_307_200.123456) < 0.000001)

        let request = try #require(StoresMockURLProtocol.requests.last)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/rest/v1/store")
        #expect(query(request, "on_conflict") == nil)
        #expect(query(request, "select") == "*")
        #expect(request.value(forHTTPHeaderField: "Prefer")?.contains("resolution=") != true)
        #expect(request.value(forHTTPHeaderField: "Prefer")?.contains("return=representation") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-access-token")
        let body = try body(request)
        #expect(body["user_id"] as? String == userID.uuidString)
        #expect(body["google_place_id"] as? String == "place-123")
        #expect(body["name"] as? String == "喫茶テスト")
        #expect(body["category"] as? String == "カフェ・喫茶")
        #expect(body["reputation"] as? Int == 4)
        #expect(body["memo"] as? String == "また行きたい")
        #expect(body["repeat_num"] as? Int == 2)
        #expect(body["latitude"] as? Double == 35)
        #expect(body["longitude"] as? Double == 139)
        #expect(body["id"] == nil)
        #expect(body["created_at"] == nil)
    }

    @Test func resavingGoogleStoreLooksUpOwnRowAndUpdatesSpecifiedVisitCount() async throws {
        let (repository, session) = try await makeRepository()
        defer { session.invalidateAndCancel() }
        let first = try await repository.saveStore(input())
        var edited = input()
        edited.repeatNum = 7
        let second = try await repository.saveStore(edited)
        #expect(first.id == second.id)
        #expect(first.createdAt == second.createdAt)
        let requests = StoresMockURLProtocol.requests
        #expect(requests.map(\.httpMethod) == ["GET", "POST", "GET", "PATCH"])
        for request in requests where request.httpMethod == "GET" {
            #expect(query(request, "user_id")?.lowercased() == "eq.\(userID.uuidString.lowercased())")
            #expect(query(request, "google_place_id") == "eq.place-123")
            #expect(query(request, "select") == "id")
            #expect(query(request, "limit") == "2")
        }
        let update = try #require(requests.last)
        #expect(query(update, "id")?.lowercased() == "eq.\(storeID.uuidString.lowercased())")
        #expect(query(update, "user_id")?.lowercased() == "eq.\(userID.uuidString.lowercased())")
        #expect(try body(update)["repeat_num"] as? Int == 7)
        for request in requests where request.httpMethod != "GET" {
            #expect(try body(request)["id"] == nil)
            #expect(try body(request)["created_at"] == nil)
        }
    }

    @Test func manualStoreInsertsWithoutConflictKeyAndEncodesNulls() async throws {
        let (repository, session) = try await makeRepository()
        defer { session.invalidateAndCancel() }
        var manual = input()
        manual.googlePlaceID = " \n\t "
        manual.reputation = nil
        manual.memo = nil
        _ = try await repository.saveStore(manual)
        let request = try #require(StoresMockURLProtocol.requests.last)
        #expect(request.httpMethod == "POST")
        #expect(query(request, "on_conflict") == nil)
        #expect(request.value(forHTTPHeaderField: "Prefer")?.contains("resolution=") != true)
        let body = try body(request)
        #expect(body["google_place_id"] is NSNull)
        #expect(body["reputation"] is NSNull)
        #expect(body["memo"] is NSNull)
    }

    @Test func existingGoogleStoreIsUpdatedWithoutInserting() async throws {
        let (repository, session) = try await makeRepository(existingIDs: [storeID])
        defer { session.invalidateAndCancel() }
        _ = try await repository.saveStore(input())
        #expect(StoresMockURLProtocol.requests.map(\.httpMethod) == ["GET", "PATCH"])
        let update = try #require(StoresMockURLProtocol.requests.last)
        #expect(query(update, "id")?.lowercased() == "eq.\(storeID.uuidString.lowercased())")
    }

    @Test func multipleGoogleMatchesRequireExplicitIDWithoutWriting() async throws {
        let (repository, session) = try await makeRepository(existingIDs: [storeID, UUID()])
        defer { session.invalidateAndCancel() }
        await #expect(throws: StoreSaveError.ambiguousGooglePlaceID) {
            try await repository.saveStore(input())
        }
        #expect(StoresMockURLProtocol.requests.map(\.httpMethod) == ["GET"])
        var edited = input()
        edited.id = storeID
        _ = try await repository.saveStore(edited)
        #expect(StoresMockURLProtocol.requests.map(\.httpMethod) == ["GET", "PATCH"])
    }

    @Test func idTakesPrecedenceAndUpdateIsLimitedToCurrentUser() async throws {
        let (repository, session) = try await makeRepository()
        defer { session.invalidateAndCancel() }
        var edited = input()
        edited.id = storeID
        edited.googlePlaceID = nil
        edited.reputation = nil
        edited.memo = nil
        let saved = try await repository.saveStore(edited)
        #expect(saved.id == storeID)
        let request = try #require(StoresMockURLProtocol.requests.last)
        #expect(request.httpMethod == "PATCH")
        #expect(query(request, "id")?.lowercased() == "eq.\(storeID.uuidString.lowercased())")
        #expect(query(request, "user_id")?.lowercased() == "eq.\(userID.uuidString.lowercased())")
        #expect(query(request, "on_conflict") == nil)
        let body = try body(request)
        #expect(body["id"] == nil)
        #expect(body["created_at"] == nil)
        #expect(body["reputation"] is NSNull)
        #expect(body["memo"] is NSNull)
        #expect(body["google_place_id"] is NSNull)

        edited.googlePlaceID = "place-123"
        _ = try await repository.saveStore(edited)
        #expect(StoresMockURLProtocol.requests.last?.httpMethod == "PATCH")
    }

    @Test func invalidInputDoesNotSendRequests() async throws {
        let (repository, session) = try await makeRepository()
        defer { session.invalidateAndCancel() }
        var cases: [(StoreSaveInput, StoreSaveError)] = []
        var invalid = input(); invalid.name = " \n\t "; cases.append((invalid, .invalidName))
        invalid = input(); invalid.category = "\n"; cases.append((invalid, .invalidCategory))
        for rating in [0, 6] {
            invalid = input(); invalid.reputation = rating; cases.append((invalid, .invalidReputation))
        }
        for count in [0, -1] {
            invalid = input(); invalid.repeatNum = count; cases.append((invalid, .invalidRepeatNum))
        }
        for latitude in [-90.1, 90.1, .nan, .infinity, -.infinity] {
            invalid = input(); invalid.latitude = latitude; cases.append((invalid, .invalidCoordinate))
        }
        for longitude in [-180.1, 180.1, .nan, .infinity, -.infinity] {
            invalid = input(); invalid.longitude = longitude; cases.append((invalid, .invalidCoordinate))
        }
        for (value, expected) in cases {
            await #expect(throws: expected) { try await repository.saveStore(value) }
        }
        #expect(StoresMockURLProtocol.requests.isEmpty)
    }

    @Test func boundaryValuesAndDefaultsAreAccepted() async throws {
        let (repository, session) = try await makeRepository()
        defer { session.invalidateAndCancel() }
        var value = StoreSaveInput(name: "店舗", category: "その他", latitude: -90, longitude: -180)
        #expect(value.repeatNum == 1)
        #expect(value.reputation == nil)
        #expect(value.googlePlaceID == nil)
        value.reputation = 1
        _ = try await repository.saveStore(value)
        value.latitude = 90
        value.longitude = 180
        value.reputation = 5
        _ = try await repository.saveStore(value)
        #expect(StoresMockURLProtocol.requests.count == 2)
    }

    @Test func signedOutUserDoesNotSendSaveRequest() async throws {
        let (repository, session) = try await makeRepository(signedIn: false)
        defer { session.invalidateAndCancel() }
        await #expect(throws: AuthError.self) { try await repository.saveStore(input()) }
        #expect(StoresMockURLProtocol.requests.isEmpty)
    }

    @Test func missingOrInaccessibleUpdateThrowsNotFound() async throws {
        let (repository, session) = try await makeRepository(response: Data("[]".utf8))
        defer { session.invalidateAndCancel() }
        var value = input()
        value.id = storeID
        await #expect(throws: StoreSaveError.notFound) { try await repository.saveStore(value) }
    }

    @Test func databaseDenialIsPropagated() async throws {
        let response = Data(#"{"code":"42501","message":"new row violates row-level security policy","details":null,"hint":null}"#.utf8)
        let (repository, session) = try await makeRepository(status: 403, response: response)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await repository.saveStore(input())
            Issue.record("DBエラーがthrowされませんでした")
        } catch let error as PostgrestError {
            #expect(error.code == "42501")
        }
    }

    @Test func networkFailureIsPropagated() async throws {
        let (repository, session) = try await makeRepository(networkError: true)
        defer { session.invalidateAndCancel() }
        await #expect(throws: URLError.self) { try await repository.saveStore(input()) }
    }

    @Test func invalidResponseIsPropagated() async throws {
        let (repository, session) = try await makeRepository(response: Data(#"{"id":"invalid"}"#.utf8))
        defer { session.invalidateAndCancel() }
        await #expect(throws: DecodingError.self) { try await repository.saveStore(input()) }
    }

    @Test func nullableFieldsAndTimestampWithoutFractionsDecode() async throws {
        let json = recordJSON()
            .replacingOccurrences(of: "\"reputation\":4", with: "\"reputation\":null")
            .replacingOccurrences(of: "\"memo\":\"また行きたい\"", with: "\"memo\":null")
            .replacingOccurrences(of: "\"google_place_id\":\"place-123\"", with: "\"google_place_id\":null")
            .replacingOccurrences(of: ".123456", with: "")
        let (repository, session) = try await makeRepository(response: Data(json.utf8))
        defer { session.invalidateAndCancel() }
        let saved = try await repository.saveStore(input())
        #expect(saved.reputation == nil)
        #expect(saved.memo == nil)
        #expect(saved.googlePlaceID == nil)
        #expect(saved.createdAt == Date(timeIntervalSince1970: 1_761_307_200))
    }

    @Test func existingSchemaAllowsNullableLocationCategoryAndDecimalRating() async throws {
        let json = recordJSON()
            .replacingOccurrences(of: "\"category\":\"カフェ・喫茶\"", with: "\"category\":null")
            .replacingOccurrences(of: "\"latitude\":35", with: "\"latitude\":null")
            .replacingOccurrences(of: "\"longitude\":139", with: "\"longitude\":null")
            .replacingOccurrences(of: "\"reputation\":4", with: "\"reputation\":4.5")
            .replacingOccurrences(of: "\"repeat_num\":2", with: "\"repeat_num\":0")
        let (repository, session) = try await makeRepository(response: Data(json.utf8))
        defer { session.invalidateAndCancel() }
        let saved = try await repository.saveStore(input())
        #expect(saved.category == nil)
        #expect(saved.latitude == nil)
        #expect(saved.longitude == nil)
        #expect(saved.reputation == 4.5)
        #expect(saved.repeatNum == 0)
    }

    private func input() -> StoreSaveInput {
        StoreSaveInput(name: " 喫茶テスト\n", category: "カフェ・喫茶", reputation: 4,
                       googlePlaceID: " place-123 ", memo: "また行きたい", repeatNum: 2,
                       latitude: 35, longitude: 139)
    }

    private func recordJSON() -> String {
        """
        {"id":"\(storeID)","name":"喫茶テスト","category":"カフェ・喫茶","reputation":4,
        "user_id":"\(userID)","google_place_id":"place-123","memo":"また行きたい",
        "repeat_num":2,"latitude":35,"longitude":139,"created_at":"2025-10-24T12:00:00.123456+00:00"}
        """
    }

    private func makeRepository(
        signedIn: Bool = true, status: Int = 200, response: Data? = nil, networkError: Bool = false,
        existingIDs: [UUID] = []
    ) async throws -> (RecordRepository, URLSession) {
        let record = response ?? Data(recordJSON().utf8)
        let savedID = storeID
        let expiry = Date().timeIntervalSince1970 + 3600
        let auth = Data("""
        {"access_token":"test-access-token","token_type":"bearer","refresh_token":"test-refresh-token",
        "expires_in":3600,"expires_at":\(expiry),"user":{"id":"\(userID)","aud":"authenticated",
        "role":"authenticated","app_metadata":{},"user_metadata":{},
        "created_at":"2025-10-24T12:00:00Z","updated_at":"2025-10-24T12:00:00Z","is_anonymous":false}}
        """.utf8)
        StoresMockURLProtocol.reset { request in
            if request.url?.path == "/auth/v1/token" { return (200, auth) }
            guard request.url?.path == "/rest/v1/store" else { throw URLError(.unsupportedURL) }
            if networkError { throw URLError(.notConnectedToInternet) }
            if request.httpMethod == "GET", status == 200 {
                let hasInserted = StoresMockURLProtocol.requests.contains { $0.httpMethod == "POST" }
                let ids = hasInserted ? [savedID] : existingIDs
                let rows = ids.map { ["id": $0.uuidString] }
                return (200, try JSONSerialization.data(withJSONObject: rows))
            }
            if request.httpMethod == "PATCH", status == 200, response == nil {
                return (200, Data("[\(String(decoding: record, as: UTF8.self))]".utf8))
            }
            return (status, record)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StoresMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://stores-tests.invalid")!, supabaseKey: "test-anon-key",
            options: .init(auth: .init(storage: StoresTestAuthStorage(), autoRefreshToken: false),
                           global: .init(session: session))
        )
        if signedIn { _ = try await client.auth.signIn(email: "test@example.com", password: "test-password") }
        return (RecordRepository(client: client), session)
    }

    private func query(_ request: URLRequest, _ name: String) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class StoresTestAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }
    func retrieve(key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }
    func remove(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = nil
    }
}

private final class StoresMockURLProtocol: URLProtocol {
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
            if captured.url?.path == "/rest/v1/store" { Self.recordedRequests.append(captured) }
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
