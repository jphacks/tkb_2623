import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Supabase
import Testing
@testable import GourmetShareMap

// URLProtocolの共有ハンドラを使うため、このスイート内は直列実行する。
@Suite(.serialized)
struct UserRepositoryTests {
    private let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    @Test func fetchMyProfileReturnsOwnRowWithAllFields() async throws {
        let (repository, session) = try await makeRepository()
        defer { session.invalidateAndCancel() }
        let profile = try await repository.fetchMyProfile()
        #expect(profile.id == userID)
        #expect(profile.name == "テスト太郎")
        #expect(profile.bio == "よろしくお願いします")
        #expect(profile.profileImage == "\(userID)/icon.jpg")

        let request = try #require(UserMockURLProtocol.requests.last)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/rest/v1/user")
        #expect(query(request, "id")?.lowercased() == "eq.\(userID.uuidString.lowercased())")
        #expect(query(request, "select") == "id,name,bio,profile_image")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-access-token")
    }

    @Test func fetchMyProfileDecodesNullableFields() async throws {
        let json = """
        {"id":"\(userID)","name":null,"bio":null,"profile_image":null}
        """
        let (repository, session) = try await makeRepository(response: Data(json.utf8))
        defer { session.invalidateAndCancel() }
        let profile = try await repository.fetchMyProfile()
        #expect(profile.id == userID)
        #expect(profile.name == nil)
        #expect(profile.bio == nil)
        #expect(profile.profileImage == nil)
    }

    @Test func fetchMyProfileRequiresAuthentication() async throws {
        let (repository, session) = try await makeRepository(signedIn: false)
        defer { session.invalidateAndCancel() }
        await #expect(throws: AuthError.self) { try await repository.fetchMyProfile() }
        #expect(UserMockURLProtocol.requests.isEmpty)
    }

    @Test func fetchMyProfileThrowsWhenRowIsNotVisible() async throws {
        // RLS（auth.uid() = id）により自分の行が存在しない場合、PostgRESTは
        // single()が要求する単一オブジェクト応答に対して0件エラー（PGRST116, 406）を返す。
        let response = Data(#"{"code":"PGRST116","details":"Results contain 0 rows","hint":null,"message":"JSON object requested, multiple (or no) rows returned"}"#.utf8)
        let (repository, session) = try await makeRepository(status: 406, response: response)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await repository.fetchMyProfile()
            Issue.record("行が存在しない場合のエラーがthrowされませんでした")
        } catch let error as PostgrestError {
            #expect(error.code == "PGRST116")
        }
    }

    @Test func fetchMyProfilePropagatesDatabaseDenial() async throws {
        let response = Data(#"{"code":"42501","message":"new row violates row-level security policy","details":null,"hint":null}"#.utf8)
        let (repository, session) = try await makeRepository(status: 403, response: response)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await repository.fetchMyProfile()
            Issue.record("DBエラーがthrowされませんでした")
        } catch let error as PostgrestError {
            #expect(error.code == "42501")
        }
    }

    @Test func fetchMyProfilePropagatesNetworkFailure() async throws {
        let (repository, session) = try await makeRepository(networkError: true)
        defer { session.invalidateAndCancel() }
        await #expect(throws: URLError.self) { try await repository.fetchMyProfile() }
    }

    private func profileJSON() -> String {
        """
        {"id":"\(userID)","name":"テスト太郎","bio":"よろしくお願いします","profile_image":"\(userID)/icon.jpg"}
        """
    }

    private func makeRepository(
        signedIn: Bool = true, status: Int = 200, response: Data? = nil, networkError: Bool = false
    ) async throws -> (UserRepository, URLSession) {
        let record = response ?? Data(profileJSON().utf8)
        let expiry = Date().timeIntervalSince1970 + 3600
        let auth = Data("""
        {"access_token":"test-access-token","token_type":"bearer","refresh_token":"test-refresh-token",
        "expires_in":3600,"expires_at":\(expiry),"user":{"id":"\(userID)","aud":"authenticated",
        "role":"authenticated","app_metadata":{},"user_metadata":{},
        "created_at":"2025-10-24T12:00:00Z","updated_at":"2025-10-24T12:00:00Z","is_anonymous":false}}
        """.utf8)
        UserMockURLProtocol.reset { request in
            if request.url?.path == "/auth/v1/token" { return (200, auth) }
            guard request.url?.path == "/rest/v1/user" else { throw URLError(.unsupportedURL) }
            if networkError { throw URLError(.notConnectedToInternet) }
            return (status, record)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UserMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://user-tests.invalid")!, supabaseKey: "test-anon-key",
            options: .init(auth: .init(storage: UserTestAuthStorage(), autoRefreshToken: false),
                           global: .init(session: session))
        )
        if signedIn { _ = try await client.auth.signIn(email: "test@example.com", password: "test-password") }
        return (UserRepository(client: client), session)
    }

    private func query(_ request: URLRequest, _ name: String) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }
}

private final class UserTestAuthStorage: AuthLocalStorage, @unchecked Sendable {
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

private final class UserMockURLProtocol: URLProtocol {
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
            Self.lock.lock()
            let handler = Self.handler
            if request.url?.path == "/rest/v1/user" { Self.recordedRequests.append(request) }
            Self.lock.unlock()
            guard let handler else { throw URLError(.unsupportedURL) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
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
