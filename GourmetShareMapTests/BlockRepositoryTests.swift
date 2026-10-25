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
struct BlockRepositoryTests {
    private let myID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let targetID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    // MARK: - block

    @Test func blockCallsRPCWithTargetID() async throws {
        let (repository, session) = try await makeRepository()
        defer { session.invalidateAndCancel() }
        try await repository.block(userID: targetID)

        let request = try #require(BlockMockURLProtocol.requests.last)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/rest/v1/rpc/block_user")
        #expect(try body(request)["target_id"] as? String == targetID.uuidString)
    }

    @Test func blockRequiresAuthentication() async throws {
        let (repository, session) = try await makeRepository(signedIn: false)
        defer { session.invalidateAndCancel() }
        await #expect(throws: AuthError.self) { try await repository.block(userID: targetID) }
        #expect(BlockMockURLProtocol.requests.isEmpty)
    }

    @Test func blockPropagatesDatabaseDenial() async throws {
        let response = Data(#"{"code":"42501","message":"new row violates row-level security policy","details":null,"hint":null}"#.utf8)
        let (repository, session) = try await makeRepository(fault: .rpcDenied, rpcResponse: response)
        defer { session.invalidateAndCancel() }
        do {
            try await repository.block(userID: targetID)
            Issue.record("DBエラーがthrowされませんでした")
        } catch let error as PostgrestError {
            #expect(error.code == "42501")
        }
    }

    // MARK: - unblock

    @Test func unblockDeletesOwnBlockedUserRow() async throws {
        let (repository, session) = try await makeRepository()
        defer { session.invalidateAndCancel() }
        try await repository.unblock(userID: targetID)

        let request = try #require(BlockMockURLProtocol.requests.last)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/rest/v1/blocked_user")
        #expect(query(request, "blocker_id")?.lowercased() == "eq.\(myID.uuidString.lowercased())")
        #expect(query(request, "blocked_id")?.lowercased() == "eq.\(targetID.uuidString.lowercased())")
    }

    @Test func unblockRequiresAuthentication() async throws {
        let (repository, session) = try await makeRepository(signedIn: false)
        defer { session.invalidateAndCancel() }
        await #expect(throws: AuthError.self) { try await repository.unblock(userID: targetID) }
        #expect(BlockMockURLProtocol.requests.isEmpty)
    }

    // MARK: - fetchBlockedUsers

    @Test func fetchBlockedUsersReturnsNamesSortedByNewest() async throws {
        let (repository, session) = try await makeRepository(
            blockedUserRows: [
                (targetID, "2026-02-01T00:00:00Z"),
                (UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, "2026-03-01T00:00:00Z"),
            ],
            userNames: [targetID: "太郎", UUID(uuidString: "33333333-3333-3333-3333-333333333333")!: "花子"]
        )
        defer { session.invalidateAndCancel() }

        let blocked = try await repository.fetchBlockedUsers()
        #expect(blocked.map(\.name) == ["太郎", "花子"])

        let listRequest = try #require(BlockMockURLProtocol.requests.first { $0.url?.path == "/rest/v1/blocked_user" })
        #expect(query(listRequest, "blocker_id")?.lowercased() == "eq.\(myID.uuidString.lowercased())")
        #expect(query(listRequest, "order") == "created_at.desc.nullslast")
    }

    @Test func fetchBlockedUsersWithNoRowsSkipsNameLookup() async throws {
        let (repository, session) = try await makeRepository(blockedUserRows: [])
        defer { session.invalidateAndCancel() }

        let blocked = try await repository.fetchBlockedUsers()
        #expect(blocked.isEmpty)
        #expect(!BlockMockURLProtocol.requests.contains { $0.url?.path == "/rest/v1/user" })
    }

    @Test func fetchBlockedUsersRequiresAuthentication() async throws {
        let (repository, session) = try await makeRepository(signedIn: false)
        defer { session.invalidateAndCancel() }
        await #expect(throws: AuthError.self) { try await repository.fetchBlockedUsers() }
        #expect(BlockMockURLProtocol.requests.isEmpty)
    }

    // MARK: - helpers

    enum Fault: Sendable { case none, rpcDenied }

    private func makeRepository(
        signedIn: Bool = true,
        fault: Fault = .none,
        rpcResponse: Data? = nil,
        blockedUserRows: [(UUID, String)] = [],
        userNames: [UUID: String] = [:]
    ) async throws -> (BlockRepository, URLSession) {
        let expiry = Date().timeIntervalSince1970 + 3600
        let auth = Data("""
        {"access_token":"test-access-token","token_type":"bearer","refresh_token":"test-refresh-token",
        "expires_in":3600,"expires_at":\(expiry),"user":{"id":"\(myID)","aud":"authenticated",
        "role":"authenticated","app_metadata":{},"user_metadata":{},
        "created_at":"2025-10-24T12:00:00Z","updated_at":"2025-10-24T12:00:00Z","is_anonymous":false}}
        """.utf8)

        let blockedUserJSON = blockedUserRows.map { id, createdAt in
            "{\"blocked_id\":\"\(id)\",\"created_at\":\"\(createdAt)\"}"
        }.joined(separator: ",")

        let userNamesJSON = userNames.map { id, name in
            "{\"id\":\"\(id)\",\"name\":\"\(name)\"}"
        }.joined(separator: ",")

        BlockMockURLProtocol.reset { request in
            let route = request.url!.path
            if route == "/auth/v1/token" { return (200, auth) }

            if route == "/rest/v1/rpc/block_user" {
                if fault == .rpcDenied, let rpcResponse { return (403, rpcResponse) }
                return (200, Data("null".utf8))
            }
            if route == "/rest/v1/blocked_user" {
                if request.httpMethod == "DELETE" { return (204, Data()) }
                return (200, Data("[\(blockedUserJSON)]".utf8))
            }
            if route == "/rest/v1/user" {
                return (200, Data("[\(userNamesJSON)]".utf8))
            }
            throw URLError(.unsupportedURL)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BlockMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://block-tests.invalid")!, supabaseKey: "test-anon-key",
            options: .init(auth: .init(storage: BlockTestAuthStorage(), autoRefreshToken: false),
                           global: .init(session: session))
        )
        if signedIn { _ = try await client.auth.signIn(email: "test@example.com", password: "test-password") }
        return (BlockRepository(client: client), session)
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

private final class BlockTestAuthStorage: AuthLocalStorage, @unchecked Sendable {
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

private final class BlockMockURLProtocol: URLProtocol {
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
