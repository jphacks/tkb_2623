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
struct TimelineRepositoryTests {
    private let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let friendID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let unknownUserID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!

    private let storeMineID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let storeFriendID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    private let storeUnknownUserID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!

    private let since = Date(timeIntervalSince1970: 1_761_000_000)

    // MARK: - fetchFeed: 変換ロジック

    @Test func fetchFeedMarksIsMineAssignsNamesAndResolvesFirstCoverImage() async throws {
        var scenario = Scenario()
        scenario.storesBody = Data("""
        [\(storeJSON(id: storeMineID, userID: userID, name: "自分の店", createdAt: "2026-10-24T13:00:00+00:00")),
         \(storeJSON(id: storeFriendID, userID: friendID, name: "フレンドの店", createdAt: "2026-10-24T12:00:00+00:00"))]
        """.utf8)
        scenario.friendCount = 2
        scenario.usersBody = Data("""
        [{"id":"\(userID)","name":"ゆい","profile_image":"me/avatar.jpg"},
         {"id":"\(friendID)","name":"はる","profile_image":"friend/avatar.jpg"}]
        """.utf8)
        // 1店舗に2枚。created_at昇順で先頭に来た方が表紙（最初にアップロードした写真）になる。
        scenario.imagesBody = Data("""
        [{"id":"\(UUID())","store_id":"\(storeFriendID)","image":"friend/first.jpg","created_at":"2026-10-20T00:00:00+00:00"},
         {"id":"\(UUID())","store_id":"\(storeFriendID)","image":"friend/second.jpg","created_at":"2026-10-21T00:00:00+00:00"}]
        """.utf8)
        scenario.recordSignedBody = signedURLsJSON([
            ("friend/first.jpg", "/object/sign/record-images/friend/first.jpg?token=first"),
            ("friend/second.jpg", "/object/sign/record-images/friend/second.jpg?token=second"),
        ])
        scenario.profileSignedBody = signedURLsJSON([
            ("me/avatar.jpg", "/object/sign/profile-images/me/avatar.jpg?token=me"),
            ("friend/avatar.jpg", "/object/sign/profile-images/friend/avatar.jpg?token=friend"),
        ])

        let (repository, session) = try await makeRepository(scenario: scenario)
        defer { session.invalidateAndCancel() }

        let feed = try await repository.fetchFeed(since: since)

        #expect(feed.friendCount == 2)
        #expect(feed.posts.count == 2)

        let mine = try #require(feed.posts.first { $0.id == storeMineID })
        #expect(mine.isMine)
        #expect(mine.storeName == "自分の店")
        #expect(mine.userName == "ゆい")
        #expect(mine.userAvatarURL?.path == "/storage/v1/object/sign/profile-images/me/avatar.jpg")
        #expect(mine.userAvatarURL?.query?.contains("token=me") == true)
        // 写真を1枚もアップロードしていない店舗には表紙がない。
        #expect(mine.coverImageURL == nil)

        let friend = try #require(feed.posts.first { $0.id == storeFriendID })
        #expect(!friend.isMine)
        #expect(friend.userName == "はる")
        #expect(friend.userAvatarURL?.path == "/storage/v1/object/sign/profile-images/friend/avatar.jpg")
        #expect(friend.coverImageURL?.path == "/storage/v1/object/sign/record-images/friend/first.jpg")
        #expect(friend.coverImageURL?.query?.contains("token=first") == true)
    }

    @Test func fetchFeedTreatsEmptyNameAndMissingUserRowAsNil() async throws {
        var scenario = Scenario()
        scenario.storesBody = Data("""
        [\(storeJSON(id: storeFriendID, userID: friendID, name: "名無しさんの店", createdAt: "2026-10-24T12:00:00+00:00")),
         \(storeJSON(id: storeUnknownUserID, userID: unknownUserID, name: "謎の店", createdAt: "2026-10-24T11:00:00+00:00"))]
        """.utf8)
        // friendIDの行は取得できるが名前が空文字。unknownUserIDの行はRLSなどで取得できない想定。
        scenario.usersBody = Data("""
        [{"id":"\(friendID)","name":"","profile_image":null}]
        """.utf8)

        let (repository, session) = try await makeRepository(scenario: scenario)
        defer { session.invalidateAndCancel() }

        let feed = try await repository.fetchFeed(since: since)

        let emptyName = try #require(feed.posts.first { $0.id == storeFriendID })
        #expect(emptyName.userName == nil)
        #expect(emptyName.userAvatarURL == nil)

        let missingUser = try #require(feed.posts.first { $0.id == storeUnknownUserID })
        #expect(missingUser.userName == nil)
        #expect(missingUser.userAvatarURL == nil)
        #expect(missingUser.coverImageURL == nil)

        // アイコンのパスを持つユーザーがいないため、署名APIへのリクエストは発生しない。
        #expect(!TimelineMockURLProtocol.requests.contains { $0.url?.path == "/storage/v1/object/sign/profile-images" })
    }

    @Test func fetchFeedFallsBackToNilAvatarWhenSigningFails() async throws {
        var scenario = Scenario()
        scenario.storesBody = Data(
            "[\(storeJSON(id: storeMineID, userID: userID, name: "自分の店", createdAt: "2026-10-24T12:00:00+00:00"))]".utf8
        )
        scenario.usersBody = Data("""
        [{"id":"\(userID)","name":"ゆい","profile_image":"me/avatar.jpg"}]
        """.utf8)
        scenario.profileSignedStatus = 403
        scenario.profileSignedBody = Data(#"{"statusCode":"403","message":"denied","error":"Unauthorized"}"#.utf8)

        let (repository, session) = try await makeRepository(scenario: scenario)
        defer { session.invalidateAndCancel() }

        // アイコンは表示の補助なので、署名に失敗してもフィード全体は失敗せず頭文字アイコンにフォールバックする。
        let feed = try await repository.fetchFeed(since: since)
        #expect(feed.posts.first?.userName == "ゆい")
        #expect(feed.posts.first?.userAvatarURL == nil)
    }

    @Test func fetchFeedSkipsUserAndImageQueriesWhenNoStores() async throws {
        var scenario = Scenario()
        scenario.friendCount = 3

        let (repository, session) = try await makeRepository(scenario: scenario)
        defer { session.invalidateAndCancel() }

        let feed = try await repository.fetchFeed(since: since)
        #expect(feed.posts.isEmpty)
        #expect(feed.friendCount == 3)

        let paths = Set(TimelineMockURLProtocol.requests.compactMap { $0.url?.path })
        #expect(paths == ["/rest/v1/store", "/rest/v1/friend"])
    }

    // MARK: - fetchFeed: 認証・エラー伝播

    @Test func fetchFeedRequiresAuthentication() async throws {
        let (repository, session) = try await makeRepository(signedIn: false)
        defer { session.invalidateAndCancel() }
        await #expect(throws: AuthError.self) { try await repository.fetchFeed(since: since) }
        #expect(TimelineMockURLProtocol.requests.isEmpty)
    }

    @Test(arguments: [Fault.database, .network])
    func fetchFeedPropagatesStoreQueryFailure(fault: Fault) async throws {
        var scenario = Scenario()
        switch fault {
        case .network:
            scenario.networkErrorPath = "/rest/v1/store"
        case .database:
            scenario.storesStatus = 403
            scenario.storesBody = Data(#"{"code":"42501","message":"denied"}"#.utf8)
        }

        let (repository, session) = try await makeRepository(scenario: scenario)
        defer { session.invalidateAndCancel() }

        switch fault {
        case .network: await #expect(throws: URLError.self) { try await repository.fetchFeed(since: since) }
        case .database: await #expect(throws: PostgrestError.self) { try await repository.fetchFeed(since: since) }
        }
    }

    @Test func fetchFeedPropagatesFriendCountQueryFailure() async throws {
        var scenario = Scenario()
        scenario.friendStatus = 403
        scenario.friendBody = Data(#"{"code":"42501","message":"denied"}"#.utf8)

        let (repository, session) = try await makeRepository(scenario: scenario)
        defer { session.invalidateAndCancel() }
        await #expect(throws: PostgrestError.self) { try await repository.fetchFeed(since: since) }
    }

    @Test func fetchFeedPropagatesUserQueryFailure() async throws {
        var scenario = Scenario()
        scenario.storesBody = Data(
            "[\(storeJSON(id: storeMineID, userID: userID, name: "自分の店", createdAt: "2026-10-24T12:00:00+00:00"))]".utf8
        )
        scenario.usersStatus = 403
        scenario.usersBody = Data(#"{"code":"42501","message":"denied"}"#.utf8)

        let (repository, session) = try await makeRepository(scenario: scenario)
        defer { session.invalidateAndCancel() }
        await #expect(throws: PostgrestError.self) { try await repository.fetchFeed(since: since) }
    }

    @Test func fetchFeedPropagatesCoverImageQueryFailure() async throws {
        var scenario = Scenario()
        scenario.storesBody = Data(
            "[\(storeJSON(id: storeMineID, userID: userID, name: "自分の店", createdAt: "2026-10-24T12:00:00+00:00"))]".utf8
        )
        scenario.imagesStatus = 403
        scenario.imagesBody = Data(#"{"code":"42501","message":"denied"}"#.utf8)

        let (repository, session) = try await makeRepository(scenario: scenario)
        defer { session.invalidateAndCancel() }
        await #expect(throws: PostgrestError.self) { try await repository.fetchFeed(since: since) }
    }

    @Test func fetchFeedPropagatesCoverImageSigningFailure() async throws {
        var scenario = Scenario()
        scenario.storesBody = Data(
            "[\(storeJSON(id: storeMineID, userID: userID, name: "自分の店", createdAt: "2026-10-24T12:00:00+00:00"))]".utf8
        )
        scenario.imagesBody = Data("""
        [{"id":"\(UUID())","store_id":"\(storeMineID)","image":"me/first.jpg","created_at":"2026-10-20T00:00:00+00:00"}]
        """.utf8)
        scenario.recordSignedStatus = 403
        scenario.recordSignedBody = Data(#"{"statusCode":"403","message":"denied","error":"Unauthorized"}"#.utf8)

        let (repository, session) = try await makeRepository(scenario: scenario)
        defer { session.invalidateAndCancel() }
        // フレンドのアイコン署名(fetchAvatarURLs)とは異なり、表紙画像の署名失敗はフィード取得自体を失敗させる。
        await #expect(throws: StorageError.self) { try await repository.fetchFeed(since: since) }
    }

    enum Fault: Sendable { case database, network }

    // MARK: - helpers

    private func storeJSON(id: UUID, userID: UUID, name: String, createdAt: String) -> String {
        """
        {"id":"\(id)","name":"\(name)","category":"カフェ・喫茶","reputation":4,
        "user_id":"\(userID)","google_place_id":null,"memo":null,
        "repeat_num":1,"latitude":35.0,"longitude":139.0,"created_at":"\(createdAt)"}
        """
    }

    private func signedURLsJSON(_ entries: [(String, String)]) -> Data {
        let items = entries.map { "{\"path\":\"\($0.0)\",\"signedURL\":\"\($0.1)\",\"error\":null}" }
        return Data("[\(items.joined(separator: ","))]".utf8)
    }

    private struct Scenario: Sendable {
        var storesStatus = 200
        var storesBody = Data("[]".utf8)
        var friendStatus = 200
        var friendCount = 0
        var friendBody = Data()
        var usersStatus = 200
        var usersBody = Data("[]".utf8)
        var imagesStatus = 200
        var imagesBody = Data("[]".utf8)
        var recordSignedStatus = 200
        var recordSignedBody = Data("[]".utf8)
        var profileSignedStatus = 200
        var profileSignedBody = Data("[]".utf8)
        /// このパスへのリクエストは接続エラーにする。
        var networkErrorPath: String?
    }

    private nonisolated static func route(_ request: URLRequest, _ scenario: Scenario) throws -> (Int, Data, [String: String]) {
        guard let path = request.url?.path else { throw URLError(.unsupportedURL) }
        if path == scenario.networkErrorPath { throw URLError(.notConnectedToInternet) }

        switch path {
        case "/rest/v1/store":
            return (scenario.storesStatus, scenario.storesBody, [:])
        case "/rest/v1/friend":
            guard scenario.friendStatus == 200 else { return (scenario.friendStatus, scenario.friendBody, [:]) }
            let contentRange = scenario.friendCount == 0 ? "*/0" : "0-\(scenario.friendCount - 1)/\(scenario.friendCount)"
            return (200, Data(), ["Content-Range": contentRange])
        case "/rest/v1/user":
            return (scenario.usersStatus, scenario.usersBody, [:])
        case "/rest/v1/image":
            return (scenario.imagesStatus, scenario.imagesBody, [:])
        case "/storage/v1/object/sign/record-images":
            return (scenario.recordSignedStatus, scenario.recordSignedBody, [:])
        case "/storage/v1/object/sign/profile-images":
            return (scenario.profileSignedStatus, scenario.profileSignedBody, [:])
        default:
            throw URLError(.unsupportedURL)
        }
    }

    private func makeRepository(
        signedIn: Bool = true, scenario: Scenario = Scenario()
    ) async throws -> (TimelineRepository, URLSession) {
        let expiry = Date().timeIntervalSince1970 + 3600
        let auth = Data("""
        {"access_token":"test-access-token","token_type":"bearer","refresh_token":"test-refresh-token",
        "expires_in":3600,"expires_at":\(expiry),"user":{"id":"\(userID)","aud":"authenticated",
        "role":"authenticated","app_metadata":{},"user_metadata":{},
        "created_at":"2025-10-24T12:00:00Z","updated_at":"2025-10-24T12:00:00Z","is_anonymous":false}}
        """.utf8)

        TimelineMockURLProtocol.reset { request in
            if request.url?.path == "/auth/v1/token" { return (200, auth, [:]) }
            return try Self.route(request, scenario)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TimelineMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://timeline-tests.invalid")!, supabaseKey: "test-anon-key",
            options: .init(auth: .init(storage: TimelineTestAuthStorage(), autoRefreshToken: false),
                           global: .init(session: session))
        )
        if signedIn { _ = try await client.auth.signIn(email: "test@example.com", password: "test-password") }
        return (TimelineRepository(client: client), session)
    }
}

private final class TimelineTestAuthStorage: AuthLocalStorage, @unchecked Sendable {
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

private final class TimelineMockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    // 全アクセスをlockで保護する。URLProtocolのコールバックは別スレッドで実行される。
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) throws -> (Int, Data, [String: String]))?
    nonisolated(unsafe) private static var recordedRequests: [URLRequest] = []

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recordedRequests
    }

    static func reset(handler: @escaping @Sendable (URLRequest) throws -> (Int, Data, [String: String])) {
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
            if captured.url?.path != "/auth/v1/token" { Self.recordedRequests.append(captured) }
            Self.lock.unlock()
            guard let handler else { throw URLError(.unsupportedURL) }
            let (status, data, extraHeaders) = try handler(captured)
            var headerFields = ["Content-Type": "application/json"]
            for (key, value) in extraHeaders { headerFields[key] = value }
            let response = HTTPURLResponse(url: captured.url!, statusCode: status, httpVersion: nil,
                                           headerFields: headerFields)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
