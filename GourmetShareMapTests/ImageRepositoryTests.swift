import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Supabase
import Testing
@testable import GourmetShareMap

@Suite(.serialized)
@MainActor
struct ImageRepositoryTests {
    private let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let storeID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let imageID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private var path: String { "\(userID)/\(storeID)/photo.jpg".lowercased() }

    @Test(arguments: [RecordImageFormat.jpeg, .png])
    func uploadCreatesObjectThenImageRow(format: RecordImageFormat) async throws {
        let (repository, session) = try await makeRepository()
        defer { session.invalidateAndCancel() }
        let bytes = Data([1, 2, 3])
        let saved = try await repository.uploadImage(data: bytes, storeID: storeID, format: format)
        #expect(saved.id == imageID)
        #expect(saved.storeID == storeID)
        let requests = ImagesMockURLProtocol.requests
        #expect(requests.map(\.httpMethod) == ["GET", "POST", "POST"])
        #expect(query(requests[0], "user_id")?.lowercased() == "eq.\(userID.uuidString.lowercased())")
        #expect(query(requests[0], "id")?.lowercased() == "eq.\(storeID.uuidString.lowercased())")
        let multipart = try #require(requests[1].httpBody)
        #expect(multipart.range(of: bytes) != nil)
        #expect(String(decoding: multipart, as: UTF8.self).contains(format.contentType))
        #expect(requests[1].value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data;") == true)
        #expect(requests[1].value(forHTTPHeaderField: "x-upsert") == "false")
        let payload = try body(requests[2])
        let objectPath = try #require(payload["image"] as? String)
        #expect(objectPath.hasPrefix("\(userID)/\(storeID)/".lowercased()))
        #expect(objectPath.hasSuffix(".\(format.fileExtension)"))
        #expect(requests[1].url?.path == "/storage/v1/object/record-images/\(objectPath)")
        #expect(saved.path == objectPath)
        #expect(payload["store_id"] as? String == storeID.uuidString)
        #expect(payload["id"] == nil)
        #expect(payload["created_at"] == nil)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer test-access-token" })
    }

    @Test func emptyDataAndInvalidExpirationSendNothing() async throws {
        let (repository, session) = try await makeRepository()
        defer { session.invalidateAndCancel() }
        await #expect(throws: ImageRepositoryError.self) { try await repository.uploadImage(data: Data(), storeID: storeID) }
        await #expect(throws: ImageRepositoryError.self) { try await repository.signedURL(imageID: imageID, expiresIn: 0) }
        #expect(ImagesMockURLProtocol.requests.isEmpty)
    }

    @Test func signedOutCannotUploadReadOrDelete() async throws {
        let (repository, session) = try await makeRepository(signedIn: false)
        defer { session.invalidateAndCancel() }
        await #expect(throws: AuthError.self) { try await repository.uploadImage(data: Data([1]), storeID: storeID) }
        await #expect(throws: AuthError.self) { try await repository.signedURL(imageID: imageID) }
        await #expect(throws: AuthError.self) { try await repository.deleteImage(imageID: imageID) }
        #expect(ImagesMockURLProtocol.requests.isEmpty)
    }

    @Test func unownedStoreCannotUploadOrDelete() async throws {
        let (repository, session) = try await makeRepository(fault: .unowned)
        defer { session.invalidateAndCancel() }
        await #expect(throws: ImageRepositoryError.self) { try await repository.uploadImage(data: Data([1]), storeID: storeID) }
        await #expect(throws: ImageRepositoryError.self) { try await repository.deleteImage(imageID: imageID) }
        #expect(ImagesMockURLProtocol.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    @Test func failedUploadNeverInsertsRow() async throws {
        let (repository, session) = try await makeRepository(fault: .upload)
        defer { session.invalidateAndCancel() }
        await #expect(throws: StorageError.self) { try await repository.uploadImage(data: Data([1]), storeID: storeID) }
        #expect(ImagesMockURLProtocol.requests.count == 2)
    }

    @Test func failedInsertRemovesUploadedObject() async throws {
        let (repository, session) = try await makeRepository(fault: .insert)
        defer { session.invalidateAndCancel() }
        await #expect(throws: PostgrestError.self) { try await repository.uploadImage(data: Data([1]), storeID: storeID) }
        let requests = ImagesMockURLProtocol.requests
        #expect(requests.map(\.httpMethod) == ["GET", "POST", "POST", "DELETE"])
        let uploadedPath = try #require(body(requests[2])["image"] as? String)
        #expect(try body(requests[3])["prefixes"] as? [String] == [uploadedPath])
    }

    @Test func cleanupFailurePreservesBothErrorsAndPath() async throws {
        let (repository, session) = try await makeRepository(fault: .insertAndCleanup)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await repository.uploadImage(data: Data([1]), storeID: storeID)
            Issue.record("Expected failure")
        } catch let ImageRepositoryError.cleanupFailed(path, insertionError, cleanupError) {
            #expect(path.hasPrefix(userID.uuidString.lowercased()))
            #expect(insertionError is PostgrestError)
            #expect(cleanupError is StorageError)
        }
    }

    @Test(arguments: [3600, 60])
    func signedURLUsesRLSVisibleRowWithoutOwnerFilter(expiration: Int) async throws {
        // フレンドの画像は所有者検証をせず、DB・StorageのRLSに委ねる。
        let (repository, session) = try await makeRepository()
        defer { session.invalidateAndCancel() }
        let url: URL
        if expiration == 3600 { url = try await repository.signedURL(imageID: imageID) }
        else { url = try await repository.signedURL(imageID: imageID, expiresIn: expiration) }
        #expect(url.absoluteString.contains("token=test"))
        #expect(url.path == "/storage/v1/object/sign/record-images/\(path)")
        let requests = ImagesMockURLProtocol.requests
        #expect(requests.count == 2)
        #expect(query(requests[0], "id")?.lowercased() == "eq.\(imageID.uuidString.lowercased())")
        #expect(query(requests[0], "user_id") == nil)
        #expect(try body(requests[1])["expiresIn"] as? Int == expiration)
    }

    @Test func invisibleImageStopsReadAndDelete() async throws {
        let (repository, session) = try await makeRepository(fault: .missingRow)
        defer { session.invalidateAndCancel() }
        await #expect(throws: ImageRepositoryError.self) { try await repository.signedURL(imageID: imageID) }
        await #expect(throws: ImageRepositoryError.self) { try await repository.deleteImage(imageID: imageID) }
        #expect(ImagesMockURLProtocol.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    @Test func signingDenialPropagates() async throws {
        let (repository, session) = try await makeRepository(fault: .sign)
        defer { session.invalidateAndCancel() }
        await #expect(throws: StorageError.self) { try await repository.signedURL(imageID: imageID) }
    }

    @Test func deleteRemovesObjectBeforeRow() async throws {
        let (repository, session) = try await makeRepository()
        defer { session.invalidateAndCancel() }
        try await repository.deleteImage(imageID: imageID)
        let requests = ImagesMockURLProtocol.requests
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "DELETE", "DELETE"])
        #expect(try body(requests[2])["prefixes"] as? [String] == [path])
        #expect(requests[3].url?.path == "/rest/v1/image")
        #expect(query(requests[3], "id")?.lowercased() == "eq.\(imageID.uuidString.lowercased())")
        #expect(query(requests[3], "store_id")?.lowercased() == "eq.\(storeID.uuidString.lowercased())")
    }

    @Test(arguments: [Fault.remove, .invalidPath])
    func deleteFailurePreservesRow(fault: Fault) async throws {
        let (repository, session) = try await makeRepository(fault: fault)
        defer { session.invalidateAndCancel() }
        await #expect(throws: (any Error).self) { try await repository.deleteImage(imageID: imageID) }
        #expect(!ImagesMockURLProtocol.requests.contains { $0.httpMethod == "DELETE" && $0.url?.path == "/rest/v1/image" })
    }

    @Test func missingObjectStillDeletesRow() async throws {
        let (repository, session) = try await makeRepository(fault: .missingObject)
        defer { session.invalidateAndCancel() }
        try await repository.deleteImage(imageID: imageID)
        #expect(ImagesMockURLProtocol.requests.last?.url?.path == "/rest/v1/image")
    }

    @Test func failedRowDeleteCanBeRetriedAfterObjectIsGone() async throws {
        let (repository, session) = try await makeRepository(fault: .deleteOnce)
        defer { session.invalidateAndCancel() }
        await #expect(throws: PostgrestError.self) { try await repository.deleteImage(imageID: imageID) }
        try await repository.deleteImage(imageID: imageID)
        #expect(ImagesMockURLProtocol.requests.filter { $0.httpMethod == "DELETE" && $0.url?.path == "/rest/v1/image" }.count == 2)
    }

    @Test(arguments: [Fault.network, .decode, .database])
    func lookupErrorsPropagate(fault: Fault) async throws {
        let (repository, session) = try await makeRepository(fault: fault)
        defer { session.invalidateAndCancel() }
        switch fault {
        case .network: await #expect(throws: URLError.self) { try await repository.signedURL(imageID: imageID) }
        case .decode: await #expect(throws: DecodingError.self) { try await repository.signedURL(imageID: imageID) }
        default: await #expect(throws: PostgrestError.self) { try await repository.signedURL(imageID: imageID) }
        }
    }

    enum Fault: Sendable { case none, unowned, upload, insert, insertAndCleanup, missingRow, sign, remove, invalidPath, missingObject, deleteOnce, network, decode, database }

    private func makeRepository(signedIn: Bool = true, fault: Fault = .none) async throws -> (ImageRepository, URLSession) {
        let user = userID, store = storeID, image = imageID, storedPath = path
        let expiry = Date().timeIntervalSince1970 + 3600
        let auth = Data("""
        {"access_token":"test-access-token","token_type":"bearer","refresh_token":"test-refresh-token",
        "expires_in":3600,"expires_at":\(expiry),"user":{"id":"\(user)","aud":"authenticated",
        "role":"authenticated","app_metadata":{},"user_metadata":{},
        "created_at":"2025-10-24T12:00:00Z","updated_at":"2025-10-24T12:00:00Z","is_anonymous":false}}
        """.utf8)
        ImagesMockURLProtocol.reset { request in
            let route = request.url!.path
            if route == "/auth/v1/token" { return (200, auth) }
            let dbError = Data(#"{"code":"42501","message":"denied"}"#.utf8)
            let storageError = Data(#"{"statusCode":"403","message":"denied","error":"Unauthorized"}"#.utf8)
            if fault == .network { throw URLError(.notConnectedToInternet) }
            if fault == .database { return (403, dbError) }
            if fault == .decode { return (200, Data("[{}]".utf8)) }
            if route == "/rest/v1/store" {
                return (200, Data((fault == .unowned ? "[]" : "[{\"id\":\"\(store)\"}]").utf8))
            }
            if route == "/rest/v1/image" {
                if request.httpMethod == "DELETE" {
                    let attempts = ImagesMockURLProtocol.requests.filter { $0.url?.path == route && $0.httpMethod == "DELETE" }.count
                    if fault == .deleteOnce && attempts == 1 { return (403, dbError) }
                    return (200, Data("[{\"id\":\"\(image)\"}]".utf8))
                }
                if fault == .missingRow { return (200, Data("[]".utf8)) }
                if request.httpMethod == "POST", fault == .insert || fault == .insertAndCleanup { return (403, dbError) }
                var objectPath = fault == .invalidPath ? "other/other/photo.jpg" : storedPath
                if request.httpMethod == "POST", let data = request.httpBody,
                   let json = try JSONSerialization.jsonObject(with: data) as? [String: String] { objectPath = json["image"]! }
                let row = "{\"id\":\"\(image)\",\"store_id\":\"\(store)\",\"image\":\"\(objectPath)\",\"created_at\":\"2025-10-24T12:00:00.123456Z\"}"
                return (200, Data((request.httpMethod == "POST" ? row : "[\(row)]").utf8))
            }
            if route.contains("/object/sign/") {
                if fault == .sign { return (403, storageError) }
                return (200, Data("{\"signedURL\":\"/object/sign/record-images/\(storedPath)?token=test\"}".utf8))
            }
            if request.httpMethod == "DELETE" {
                if fault == .remove || fault == .insertAndCleanup { return (403, storageError) }
                let attempts = ImagesMockURLProtocol.requests.filter { $0.httpMethod == "DELETE" && $0.url?.path == "/rest/v1/image" }.count
                if fault == .missingObject || (fault == .deleteOnce && attempts > 0) {
                    return (404, Data(#"{"statusCode":"404","message":"not found","error":"not_found"}"#.utf8))
                }
                return (200, Data("[]".utf8))
            }
            if route.hasPrefix("/storage/v1/object/record-images/") {
                if fault == .upload { return (403, storageError) }
                return (200, Data("{\"Id\":\"\(image)\",\"Key\":\"record-images/uploaded.jpg\"}".utf8))
            }
            throw URLError(.unsupportedURL)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImagesMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = SupabaseClient(supabaseURL: URL(string: "https://images-tests.invalid")!, supabaseKey: "test-anon-key",
            options: .init(auth: .init(storage: ImagesTestAuthStorage(), autoRefreshToken: false), global: .init(session: session)))
        if signedIn { _ = try await client.auth.signIn(email: "test@example.com", password: "test-password") }
        return (ImageRepository(client: client), session)
    }

    private func query(_ request: URLRequest, _ name: String) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
    private func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class ImagesTestAuthStorage: AuthLocalStorage, @unchecked Sendable {
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

private final class ImagesMockURLProtocol: URLProtocol {
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
