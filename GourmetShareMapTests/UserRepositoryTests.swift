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
    private var oldPath: String { "\(userID.uuidString.lowercased())/old-icon.jpg" }

    // MARK: - fetchMyProfile

    @Test func fetchMyProfileReturnsOwnRowWithAllFields() async throws {
        let (repository, session) = try await makeRepository(existingImagePath: oldPath)
        defer { session.invalidateAndCancel() }
        let profile = try await repository.fetchMyProfile()
        #expect(profile.id == userID)
        #expect(profile.name == "テスト太郎")
        #expect(profile.bio == "よろしくお願いします")
        #expect(profile.profileImage == oldPath)

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
        let (repository, session) = try await makeRepository(fetchResponse: Data(json.utf8))
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
        let (repository, session) = try await makeRepository(fetchStatus: 406, fetchResponse: response)
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
        let (repository, session) = try await makeRepository(fetchStatus: 403, fetchResponse: response)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await repository.fetchMyProfile()
            Issue.record("DBエラーがthrowされませんでした")
        } catch let error as PostgrestError {
            #expect(error.code == "42501")
        }
    }

    @Test func fetchMyProfilePropagatesNetworkFailure() async throws {
        let (repository, session) = try await makeRepository(fault: .network)
        defer { session.invalidateAndCancel() }
        await #expect(throws: URLError.self) { try await repository.fetchMyProfile() }
    }

    // MARK: - fetchProfile(userID:)

    @Test func fetchProfileReturnsSpecifiedUsersRow() async throws {
        let friendID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let json = """
        {"id":"\(friendID)","name":"フレンド花子","bio":"そば好き","profile_image":null}
        """
        let (repository, session) = try await makeRepository(fetchResponse: Data(json.utf8))
        defer { session.invalidateAndCancel() }
        let profile = try await repository.fetchProfile(userID: friendID)
        #expect(profile.id == friendID)
        #expect(profile.name == "フレンド花子")
        #expect(profile.bio == "そば好き")
        #expect(profile.profileImage == nil)

        let request = try #require(UserMockURLProtocol.requests.last)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/rest/v1/user")
        #expect(query(request, "id")?.lowercased() == "eq.\(friendID.uuidString.lowercased())")
        #expect(query(request, "select") == "id,name,bio,profile_image")
    }

    @Test func fetchProfileThrowsWhenRowIsNotVisibleToCaller() async throws {
        // RLS（フォロー中ユーザーの行のみ参照可）により対象がフォロー相手でない場合、
        // PostgRESTはsingle()が要求する単一オブジェクト応答に対して0件エラー（PGRST116, 406）を返す。
        let response = Data(#"{"code":"PGRST116","details":"Results contain 0 rows","hint":null,"message":"JSON object requested, multiple (or no) rows returned"}"#.utf8)
        let (repository, session) = try await makeRepository(fetchStatus: 406, fetchResponse: response)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await repository.fetchProfile(userID: UUID())
            Issue.record("行が参照不可の場合のエラーがthrowされませんでした")
        } catch let error as PostgrestError {
            #expect(error.code == "PGRST116")
        }
    }

    @Test func fetchProfilePropagatesDatabaseDenial() async throws {
        let response = Data(#"{"code":"42501","message":"new row violates row-level security policy","details":null,"hint":null}"#.utf8)
        let (repository, session) = try await makeRepository(fetchStatus: 403, fetchResponse: response)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await repository.fetchProfile(userID: UUID())
            Issue.record("DBエラーがthrowされませんでした")
        } catch let error as PostgrestError {
            #expect(error.code == "42501")
        }
    }

    // MARK: - uploadProfileImage

    @Test func uploadProfileImageWithNoExistingImageSkipsDeletion() async throws {
        let (repository, session) = try await makeRepository(existingImagePath: nil)
        defer { session.invalidateAndCancel() }
        let newPath = try await repository.uploadProfileImage(data: Data([1, 2, 3]))
        #expect(newPath.hasPrefix("\(userID.uuidString.lowercased())/"))
        #expect(newPath.hasSuffix(".jpg"))

        let requests = UserMockURLProtocol.requests
        #expect(requests.map(\.httpMethod) == ["GET", "POST", "PATCH"])
        #expect(requests[1].url?.path == "/storage/v1/object/profile-images/\(newPath)")
        let patchBody = try body(requests[2])
        #expect(patchBody["profile_image"] as? String == newPath)
        #expect(!requests.contains { $0.httpMethod == "DELETE" })
    }

    @Test func uploadProfileImageDeletesOldImageAfterSuccess() async throws {
        let (repository, session) = try await makeRepository(existingImagePath: oldPath)
        defer { session.invalidateAndCancel() }
        let newPath = try await repository.uploadProfileImage(data: Data([1, 2, 3]), format: .png)
        #expect(newPath.hasSuffix(".png"))

        let requests = UserMockURLProtocol.requests
        #expect(requests.map(\.httpMethod) == ["GET", "POST", "PATCH", "DELETE"])
        let deleteRequest = try #require(requests.last)
        #expect(deleteRequest.url?.path == "/storage/v1/object/profile-images")
        #expect(try body(deleteRequest)["prefixes"] as? [String] == [oldPath])
    }

    @Test func uploadProfileImageEmptyDataThrowsWithoutRequests() async throws {
        let (repository, session) = try await makeRepository()
        defer { session.invalidateAndCancel() }
        await #expect(throws: UserRepositoryError.self) { try await repository.uploadProfileImage(data: Data()) }
        #expect(UserMockURLProtocol.requests.isEmpty)
    }

    @Test func uploadProfileImageRequiresAuthentication() async throws {
        let (repository, session) = try await makeRepository(signedIn: false)
        defer { session.invalidateAndCancel() }
        await #expect(throws: AuthError.self) { try await repository.uploadProfileImage(data: Data([1])) }
        #expect(UserMockURLProtocol.requests.isEmpty)
    }

    @Test func uploadProfileImagePropagatesUploadFailure() async throws {
        let (repository, session) = try await makeRepository(fault: .uploadDenied)
        defer { session.invalidateAndCancel() }
        await #expect(throws: StorageError.self) { try await repository.uploadProfileImage(data: Data([1])) }
        #expect(!UserMockURLProtocol.requests.contains { $0.httpMethod == "PATCH" })
    }

    @Test func uploadProfileImageRollsBackUploadWhenProfileUpdateFails() async throws {
        let (repository, session) = try await makeRepository(existingImagePath: oldPath, fault: .updateDenied)
        defer { session.invalidateAndCancel() }
        await #expect(throws: PostgrestError.self) { try await repository.uploadProfileImage(data: Data([1])) }
        let requests = UserMockURLProtocol.requests
        #expect(requests.map(\.httpMethod) == ["GET", "POST", "PATCH", "DELETE"])
        let rollback = try #require(requests.last)
        #expect(rollback.url?.path == "/storage/v1/object/profile-images")
        // ロールバックで削除されるのは直前にアップロードした新しいパスのみで、旧パスは消さない。
        let uploadRequest = try #require(requests.first { $0.httpMethod == "POST" })
        let uploadedPath = String(uploadRequest.url!.path.dropFirst("/storage/v1/object/profile-images/".count))
        #expect(try body(rollback)["prefixes"] as? [String] == [uploadedPath])
        #expect(uploadedPath != oldPath)
    }

    @Test func uploadProfileImageThrowsCleanupFailedWhenRollbackAlsoFails() async throws {
        let (repository, session) = try await makeRepository(fault: .cleanupDenied)
        defer { session.invalidateAndCancel() }
        await #expect(throws: UserRepositoryError.self) { try await repository.uploadProfileImage(data: Data([1])) }
    }

    @Test func uploadProfileImageIgnoresAlreadyDeletedOldFile() async throws {
        let (repository, session) = try await makeRepository(existingImagePath: oldPath, fault: .oldDeleteMissing)
        defer { session.invalidateAndCancel() }
        let newPath = try await repository.uploadProfileImage(data: Data([1]))
        #expect(!newPath.isEmpty)
    }

    // MARK: - signedURL

    @Test func signedURLUsesGivenPath() async throws {
        let (repository, session) = try await makeRepository()
        defer { session.invalidateAndCancel() }
        let url = try await repository.signedURL(path: oldPath)
        #expect(url.absoluteString.contains("token=test"))
        let request = try #require(UserMockURLProtocol.requests.last)
        #expect(request.url?.path == "/storage/v1/object/sign/profile-images/\(oldPath)")
    }

    @Test func signedURLInvalidExpirationThrowsWithoutRequest() async throws {
        let (repository, session) = try await makeRepository()
        defer { session.invalidateAndCancel() }
        await #expect(throws: UserRepositoryError.self) { try await repository.signedURL(path: oldPath, expiresIn: 0) }
        #expect(UserMockURLProtocol.requests.isEmpty)
    }

    @Test func signedURLRequiresAuthentication() async throws {
        let (repository, session) = try await makeRepository(signedIn: false)
        defer { session.invalidateAndCancel() }
        await #expect(throws: AuthError.self) { try await repository.signedURL(path: oldPath) }
        #expect(UserMockURLProtocol.requests.isEmpty)
    }

    @Test func signedURLPropagatesSigningDenial() async throws {
        let (repository, session) = try await makeRepository(fault: .signDenied)
        defer { session.invalidateAndCancel() }
        await #expect(throws: StorageError.self) { try await repository.signedURL(path: oldPath) }
    }

    // MARK: - helpers

    enum Fault: Sendable { case none, network, uploadDenied, updateDenied, cleanupDenied, oldDeleteMissing, signDenied }

    private func profileJSON(path: String?) -> String {
        let imageValue = path.map { "\"\($0)\"" } ?? "null"
        return """
        {"id":"\(userID)","name":"テスト太郎","bio":"よろしくお願いします","profile_image":\(imageValue)}
        """
    }

    private func makeRepository(
        signedIn: Bool = true,
        existingImagePath: String? = nil,
        fault: Fault = .none,
        fetchStatus: Int = 200,
        fetchResponse: Data? = nil
    ) async throws -> (UserRepository, URLSession) {
        let expiry = Date().timeIntervalSince1970 + 3600
        let auth = Data("""
        {"access_token":"test-access-token","token_type":"bearer","refresh_token":"test-refresh-token",
        "expires_in":3600,"expires_at":\(expiry),"user":{"id":"\(userID)","aud":"authenticated",
        "role":"authenticated","app_metadata":{},"user_metadata":{},
        "created_at":"2025-10-24T12:00:00Z","updated_at":"2025-10-24T12:00:00Z","is_anonymous":false}}
        """.utf8)
        let dbError = Data(#"{"code":"42501","message":"denied"}"#.utf8)
        let storageError = Data(#"{"statusCode":"403","message":"denied","error":"Unauthorized"}"#.utf8)
        let notFoundError = Data(#"{"statusCode":"404","message":"not found","error":"not_found"}"#.utf8)

        UserMockURLProtocol.reset { request in
            let route = request.url!.path
            if route == "/auth/v1/token" { return (200, auth) }
            if fault == .network { throw URLError(.notConnectedToInternet) }

            if route == "/rest/v1/user" {
                if request.httpMethod == "GET" {
                    if let fetchResponse { return (fetchStatus, fetchResponse) }
                    return (fetchStatus, Data(profileJSON(path: existingImagePath).utf8))
                }
                // PATCH（updateMyProfileImage）
                if fault == .updateDenied || fault == .cleanupDenied { return (403, dbError) }
                return (200, Data("[]".utf8))
            }
            if route.hasPrefix("/storage/v1/object/sign/profile-images/") {
                if fault == .signDenied { return (403, storageError) }
                let signedPath = String(route.dropFirst("/storage/v1/object/sign/profile-images/".count))
                return (200, Data("{\"signedURL\":\"/object/sign/profile-images/\(signedPath)?token=test\"}".utf8))
            }
            if route.hasPrefix("/storage/v1/object/profile-images/") {
                // アップロード（POST）
                if fault == .uploadDenied { return (403, storageError) }
                return (200, Data(#"{"Id":"33333333-3333-3333-3333-333333333333","Key":"profile-images/uploaded"}"#.utf8))
            }
            if route == "/storage/v1/object/profile-images" {
                // 削除（DELETE）。新パスのロールバック・旧パスの後始末の両方がここを通る。
                if fault == .cleanupDenied { return (403, storageError) }
                if fault == .oldDeleteMissing { return (404, notFoundError) }
                return (200, Data("[]".utf8))
            }
            throw URLError(.unsupportedURL)
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

    private func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
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
