//
//  AuthViewModelTests.swift
//  GourmetShareMapTests
//

// signInWithApple / createUserIfNeeded は ASAuthorizationAppleIDCredential を
// テストコードから構築できないため今回は対象外。
// シグネチャを変更してテスト可能にするかどうかは開発者の判断が必要なため、
// 開発者の判断を待って別タスクで対応する。

import Foundation
import Supabase
import Testing
@testable import GourmetShareMap

// URLProtocolの共有ハンドラを使うため、このスイート内は直列実行する。
// AuthViewModelは@MainActorのため、このスイートもMainActorに揃える。
@MainActor
@Suite(.serialized)
struct AuthViewModelTests {
    private let userID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    // MARK: - 初期状態

    @Test func initialStateHasNoSessionWhenNoPersistedSession() async throws {
        let (viewModel, session) = try await makeViewModel(signedIn: false)
        defer { session.invalidateAndCancel() }

        #expect(viewModel.session == nil)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.needsOnboarding == false)
    }

    // MARK: - signOut

    @Test func signOutCallsLogoutEndpointAndClearsSession() async throws {
        let (viewModel, session) = try await makeViewModel(signedIn: true)
        defer { session.invalidateAndCancel() }

        // authStateChangesからの初期セッション反映を待つ（サインイン済みであること）。
        try await waitUntil { viewModel.session != nil }
        #expect(viewModel.session != nil)

        await viewModel.signOut()

        let request = try #require(AuthMockURLProtocol.requests.last { $0.url?.path == "/auth/v1/logout" })
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-access-token")
        #expect(query(request, "scope") == "global")

        // signOut()はサインアウトイベントを直接発行するため、authStateChanges経由でnilになる。
        try await waitUntil { viewModel.session == nil }
        #expect(viewModel.session == nil)
    }

    // MARK: - helpers

    private func makeViewModel(signedIn: Bool) async throws -> (AuthViewModel, URLSession) {
        let expiry = Date().timeIntervalSince1970 + 3600
        let auth = Data("""
        {"access_token":"test-access-token","token_type":"bearer","refresh_token":"test-refresh-token",
        "expires_in":3600,"expires_at":\(expiry),"user":{"id":"\(userID)","aud":"authenticated",
        "role":"authenticated","app_metadata":{},"user_metadata":{},
        "created_at":"2025-10-24T12:00:00Z","updated_at":"2025-10-24T12:00:00Z","is_anonymous":false}}
        """.utf8)

        AuthMockURLProtocol.reset { request in
            let route = request.url!.path
            if route == "/auth/v1/token" { return (200, auth) }
            if route == "/auth/v1/logout" { return (200, Data("{}".utf8)) }
            throw URLError(.unsupportedURL)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://auth-tests.invalid")!, supabaseKey: "test-anon-key",
            options: .init(auth: .init(storage: AuthTestAuthStorage(), autoRefreshToken: false),
                           global: .init(session: session))
        )
        if signedIn {
            _ = try await client.auth.signIn(email: "test@example.com", password: "test-password")
        }
        return (AuthViewModel(client: client), session)
    }

    private func query(_ request: URLRequest, _ name: String) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }

    /// authStateChangesは非同期に伝播するため、条件が満たされるまで短い間隔でポーリングする。
    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now > deadline {
                Issue.record("条件が満たされるまでにタイムアウトしました")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class AuthTestAuthStorage: AuthLocalStorage, @unchecked Sendable {
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

private final class AuthMockURLProtocol: URLProtocol {
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
