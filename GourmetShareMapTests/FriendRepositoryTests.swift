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
struct FriendRepositoryTests {
    private let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let otherID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    // MARK: - fetchFriends

    @Test func fetchFriendsReturnsFollowedUsers() async throws {
        let json = """
        [{"created_at":"2026-10-24T12:00:00+00:00",
          "friend":{"id":"\(otherID)","user_name":"haru_01","name":"はる","profile_image":"\(otherID.uuidString.lowercased())/a.jpg"}},
         {"created_at":"2026-10-23T12:00:00+00:00","friend":null}]
        """
        let (repository, session) = try await makeRepository { _ in (200, Data(json.utf8)) }
        defer { session.invalidateAndCancel() }

        let friends = try await repository.fetchFriends()

        // RLSで相手の行が見えない（null）ものは除外する。
        #expect(friends == [
            FriendUser(id: otherID, userName: "haru_01", name: "はる", profileImage: "\(otherID.uuidString.lowercased())/a.jpg")
        ])
        let request = try #require(FriendMockURLProtocol.requests.last)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/rest/v1/friend")
        #expect(query(request, "user_id")?.lowercased() == "eq.\(userID.uuidString.lowercased())")
        #expect(query(request, "select") == "created_at,friend:user!friend_friend_id_fkey(id,user_name,name,profile_image)")
        #expect(query(request, "order")?.hasPrefix("created_at.desc") == true)
    }

    @Test func fetchFriendsRequiresAuthentication() async throws {
        let (repository, session) = try await makeRepository(signedIn: false) { _ in (200, Data("[]".utf8)) }
        defer { session.invalidateAndCancel() }
        await #expect(throws: AuthError.self) { try await repository.fetchFriends() }
        #expect(FriendMockURLProtocol.requests.isEmpty)
    }

    // MARK: - fetchIncomingRequests

    @Test func fetchIncomingRequestsReturnsRequestersAddressedToMe() async throws {
        let json = """
        [{"created_at":"2026-10-24T12:34:56.789+00:00",
          "requester":{"id":"\(otherID)","user_name":"aoi","name":null,"profile_image":null}}]
        """
        let (repository, session) = try await makeRepository { _ in (200, Data(json.utf8)) }
        defer { session.invalidateAndCancel() }

        let requests = try await repository.fetchIncomingRequests()

        #expect(requests.count == 1)
        #expect(requests.first?.requester == FriendUser(id: otherID, userName: "aoi", name: nil, profileImage: nil))
        #expect(requests.first?.requester.displayName == "aoi")
        let request = try #require(FriendMockURLProtocol.requests.last)
        #expect(request.url?.path == "/rest/v1/friend_request")
        #expect(query(request, "addressee_id")?.lowercased() == "eq.\(userID.uuidString.lowercased())")
        #expect(query(request, "select") == "created_at,requester:user!friend_request_requester_id_fkey(id,user_name,name,profile_image)")
    }

    // MARK: - searchUser

    @Test func searchUserNormalizesInputAndReturnsRelation() async throws {
        let json = """
        [{"id":"\(otherID)","user_name":"haru_01","name":"はる","profile_image":null,"relation":"incoming"}]
        """
        let (repository, session) = try await makeRepository { _ in (200, Data(json.utf8)) }
        defer { session.invalidateAndCancel() }

        let result = try await repository.searchUser(userName: "  HARU_01 ")

        #expect(result == FriendSearchResult(
            user: FriendUser(id: otherID, userName: "haru_01", name: "はる", profileImage: nil),
            relation: .incoming
        ))
        let request = try #require(FriendMockURLProtocol.requests.last)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/rest/v1/rpc/search_user_by_user_name")
        #expect(try body(request)["p_user_name"] as? String == "haru_01")
    }

    @Test func searchUserDecodesSelfRelation() async throws {
        let json = """
        [{"id":"\(userID)","user_name":"me_123","name":"自分","profile_image":null,"relation":"self"}]
        """
        let (repository, session) = try await makeRepository { _ in (200, Data(json.utf8)) }
        defer { session.invalidateAndCancel() }
        #expect(try await repository.searchUser(userName: "me_123")?.relation == .me)
    }

    @Test func searchUserReturnsNilWhenNotFound() async throws {
        let (repository, session) = try await makeRepository { _ in (200, Data("[]".utf8)) }
        defer { session.invalidateAndCancel() }
        #expect(try await repository.searchUser(userName: "nobody") == nil)
    }

    @Test(arguments: ["ab", "with-hyphen", "", "abcdefghijklmnopqrstu"])
    func searchUserRejectsInvalidInputWithoutRequest(input: String) async throws {
        let (repository, session) = try await makeRepository { _ in (200, Data("[]".utf8)) }
        defer { session.invalidateAndCancel() }
        await #expect(throws: FriendRepositoryError.invalidUserName) { try await repository.searchUser(userName: input) }
        #expect(FriendMockURLProtocol.requests.isEmpty)
    }

    // MARK: - sendRequest

    @Test(arguments: [("requested", FriendRequestSendResult.requested), ("accepted", .accepted)])
    func sendRequestReturnsResult(response: String, expected: FriendRequestSendResult) async throws {
        let (repository, session) = try await makeRepository { _ in (200, Data("\"\(response)\"".utf8)) }
        defer { session.invalidateAndCancel() }

        #expect(try await repository.sendRequest(to: otherID) == expected)
        let request = try #require(FriendMockURLProtocol.requests.last)
        #expect(request.url?.path == "/rest/v1/rpc/send_friend_request")
        #expect((try body(request)["p_addressee_id"] as? String)?.lowercased() == otherID.uuidString.lowercased())
    }

    @Test(arguments: [
        ("GSF01", FriendRepositoryError.cannotRequestSelf),
        ("GSF02", .alreadyFriends),
        ("GSF05", .userNotFound),
    ])
    func sendRequestMapsDatabaseErrors(code: String, expected: FriendRepositoryError) async throws {
        let (repository, session) = try await makeRepository { _ in
            (400, Data(#"{"code":"\#(code)","message":"error","details":null,"hint":null}"#.utf8))
        }
        defer { session.invalidateAndCancel() }
        await #expect(throws: expected) { try await repository.sendRequest(to: otherID) }
    }

    @Test func sendRequestRejectsUnknownResult() async throws {
        let (repository, session) = try await makeRepository { _ in (200, Data("\"unknown\"".utf8)) }
        defer { session.invalidateAndCancel() }
        await #expect(throws: FriendRepositoryError.unexpectedResponse) { try await repository.sendRequest(to: otherID) }
    }

    @Test func sendRequestPropagatesOtherErrors() async throws {
        let (repository, session) = try await makeRepository { _ in
            (403, Data(#"{"code":"42501","message":"permission denied"}"#.utf8))
        }
        defer { session.invalidateAndCancel() }
        await #expect(throws: PostgrestError.self) { try await repository.sendRequest(to: otherID) }
    }

    // MARK: - acceptRequest / rejectRequest

    @Test func acceptRequestCallsRPC() async throws {
        let (repository, session) = try await makeRepository { _ in (200, Data("null".utf8)) }
        defer { session.invalidateAndCancel() }

        try await repository.acceptRequest(from: otherID)

        let request = try #require(FriendMockURLProtocol.requests.last)
        #expect(request.url?.path == "/rest/v1/rpc/accept_friend_request")
        #expect((try body(request)["p_requester_id"] as? String)?.lowercased() == otherID.uuidString.lowercased())
    }

    @Test func acceptRequestMapsNotFound() async throws {
        let (repository, session) = try await makeRepository { _ in
            (400, Data(#"{"code":"GSF04","message":"friend request not found"}"#.utf8))
        }
        defer { session.invalidateAndCancel() }
        await #expect(throws: FriendRepositoryError.requestNotFound) { try await repository.acceptRequest(from: otherID) }
    }

    @Test func rejectRequestDeletesRequestAddressedToMe() async throws {
        let (repository, session) = try await makeRepository { _ in (204, Data()) }
        defer { session.invalidateAndCancel() }

        try await repository.rejectRequest(from: otherID)

        let request = try #require(FriendMockURLProtocol.requests.last)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/rest/v1/friend_request")
        #expect(query(request, "requester_id")?.lowercased() == "eq.\(otherID.uuidString.lowercased())")
        #expect(query(request, "addressee_id")?.lowercased() == "eq.\(userID.uuidString.lowercased())")
    }

    // MARK: - avatarURLs

    @Test func avatarURLsReturnsSignedURLsAndSkipsFailures() async throws {
        let json = """
        [{"path":"a/1.jpg","signedURL":"/object/sign/profile-images/a/1.jpg?token=t","error":null},
         {"path":"b/2.jpg","signedURL":null,"error":"Either the object does not exist or you do not have access to it"}]
        """
        let (repository, session) = try await makeRepository { _ in (200, Data(json.utf8)) }
        defer { session.invalidateAndCancel() }

        let urls = await repository.avatarURLs(for: ["a/1.jpg", "b/2.jpg", "a/1.jpg"])

        #expect(urls.keys.sorted() == ["a/1.jpg"])
        let request = try #require(FriendMockURLProtocol.requests.last)
        #expect(request.url?.path == "/storage/v1/object/sign/profile-images")
        // 重複したパスはまとめて1回だけ署名する。
        #expect((try body(request)["paths"] as? [String])?.sorted() == ["a/1.jpg", "b/2.jpg"])
    }

    @Test func avatarURLsReturnsEmptyOnFailureOrNoPaths() async throws {
        let (repository, session) = try await makeRepository { _ in
            (403, Data(#"{"statusCode":"403","message":"denied","error":"Unauthorized"}"#.utf8))
        }
        defer { session.invalidateAndCancel() }
        #expect(await repository.avatarURLs(for: ["a/1.jpg"]).isEmpty)
        #expect(await repository.avatarURLs(for: []).isEmpty)
    }

    // MARK: - helpers

    private func makeRepository(
        signedIn: Bool = true,
        handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)
    ) async throws -> (FriendRepository, URLSession) {
        let expiry = Date().timeIntervalSince1970 + 3600
        let auth = Data("""
        {"access_token":"test-access-token","token_type":"bearer","refresh_token":"test-refresh-token",
        "expires_in":3600,"expires_at":\(expiry),"user":{"id":"\(userID)","aud":"authenticated",
        "role":"authenticated","app_metadata":{},"user_metadata":{},
        "created_at":"2025-10-24T12:00:00Z","updated_at":"2025-10-24T12:00:00Z","is_anonymous":false}}
        """.utf8)

        FriendMockURLProtocol.reset { request in
            if request.url!.path == "/auth/v1/token" { return (200, auth) }
            return try handler(request)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FriendMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://friend-tests.invalid")!, supabaseKey: "test-anon-key",
            options: .init(auth: .init(storage: FriendTestAuthStorage(), autoRefreshToken: false),
                           global: .init(session: session))
        )
        if signedIn { _ = try await client.auth.signIn(email: "test@example.com", password: "test-password") }
        return (FriendRepository(client: client), session)
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

private final class FriendTestAuthStorage: AuthLocalStorage, @unchecked Sendable {
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

private final class FriendMockURLProtocol: URLProtocol {
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
            if captured.url?.path != "/auth/v1/token" { Self.recordedRequests.append(captured) }
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
