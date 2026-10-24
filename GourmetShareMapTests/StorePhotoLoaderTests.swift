import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Supabase
import Testing
import UIKit
@testable import GourmetShareMap

/// `StorePhotoLoader` は「image行の取得 → 署名付きURLの発行（`ImageRepository`経由）→
/// 実バイトのダウンロード（`URLSession.shared`を直接使用）」という3段の往復を行う。
/// 前半2段は`ImageRepositoryTests`と同じ手法（クライアントに差し込んだ`URLProtocol`）でモックし、
/// `URLSession.shared`を使う最後のダウンロードだけは`URLProtocol.registerClass`でグローバルに横取りする。
@Suite(.serialized)
@MainActor
struct StorePhotoLoaderTests {
    private let storeA = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    private let storeB = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    private let imageA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let imageB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    @Test func loadFetchesAndCachesThePhotoForAStoreThatHasOne() async throws {
        let (loader, session) = try await makeLoader(
            imagesByStore: [storeA: [imageA]],
            pathsByImage: [imageA: "u/\(storeA)/photo.jpg"]
        )
        defer { session.invalidateAndCancel() }
        let pngData = samplePNGData()
        PhotoDownloadMockURLProtocol.reset { _ in (200, pngData) }
        defer { PhotoDownloadMockURLProtocol.clear() }

        await loader.load(storeIDs: [storeA])

        #expect(loader.photo(for: storeA) != nil)
    }

    @Test func loadSkipsAStoreWithNoPhotosAndDoesNotRetryOnReload() async throws {
        let (loader, session) = try await makeLoader(imagesByStore: [storeA: []])
        defer { session.invalidateAndCancel() }
        PhotoDownloadMockURLProtocol.reset { _ in (200, Data()) }
        defer { PhotoDownloadMockURLProtocol.clear() }

        await loader.load(storeIDs: [storeA])
        #expect(loader.photo(for: storeA) == nil)
        let requestCount = PhotoRepoMockURLProtocol.requests.count

        // 一度「写真なし」と分かった店舗は、再度loadを呼んでもimage行を取り直さない。
        await loader.load(storeIDs: [storeA])

        #expect(loader.photo(for: storeA) == nil)
        #expect(PhotoRepoMockURLProtocol.requests.count == requestCount)
    }

    @Test func loadSkipsAStoreWhenTheImageListFetchFails() async throws {
        let (loader, session) = try await makeLoader(imagesByStore: [storeA: [imageA]], failImageList: true)
        defer { session.invalidateAndCancel() }
        let pngData = samplePNGData()
        PhotoDownloadMockURLProtocol.reset { _ in (200, pngData) }
        defer { PhotoDownloadMockURLProtocol.clear() }

        await loader.load(storeIDs: [storeA])

        #expect(loader.photo(for: storeA) == nil)
        // 失敗後に再度loadしても、skip済みのため取り直さない。
        let requestCount = PhotoRepoMockURLProtocol.requests.count
        await loader.load(storeIDs: [storeA])
        #expect(PhotoRepoMockURLProtocol.requests.count == requestCount)
    }

    @Test func loadSkipsAStoreWhenSigningTheURLFails() async throws {
        let (loader, session) = try await makeLoader(
            imagesByStore: [storeA: [imageA]],
            pathsByImage: [imageA: "u/\(storeA)/photo.jpg"],
            failSigning: true
        )
        defer { session.invalidateAndCancel() }
        let pngData = samplePNGData()
        PhotoDownloadMockURLProtocol.reset { _ in (200, pngData) }
        defer { PhotoDownloadMockURLProtocol.clear() }

        await loader.load(storeIDs: [storeA])

        #expect(loader.photo(for: storeA) == nil)
        // 署名の発行までは到達している（ダウンロード側の問題ではない）ことを確認する。
        #expect(PhotoRepoMockURLProtocol.requests.contains { $0.url?.path.contains("/object/sign/") == true })
    }

    @Test func loadSkipsAStoreWhenTheByteDownloadFails() async throws {
        let (loader, session) = try await makeLoader(
            imagesByStore: [storeA: [imageA]],
            pathsByImage: [imageA: "u/\(storeA)/photo.jpg"]
        )
        defer { session.invalidateAndCancel() }
        PhotoDownloadMockURLProtocol.reset { _ in throw URLError(.notConnectedToInternet) }
        defer { PhotoDownloadMockURLProtocol.clear() }

        await loader.load(storeIDs: [storeA])

        #expect(loader.photo(for: storeA) == nil)
    }

    @Test func loadSkipsAStoreWhenTheDownloadedDataIsNotAnImage() async throws {
        let (loader, session) = try await makeLoader(
            imagesByStore: [storeA: [imageA]],
            pathsByImage: [imageA: "u/\(storeA)/photo.jpg"]
        )
        defer { session.invalidateAndCancel() }
        PhotoDownloadMockURLProtocol.reset { _ in (200, Data("not an image".utf8)) }
        defer { PhotoDownloadMockURLProtocol.clear() }

        await loader.load(storeIDs: [storeA])

        #expect(loader.photo(for: storeA) == nil)
    }

    @Test func loadHandlesMultipleStoresIndependentlyWhenOneFails() async throws {
        let (loader, session) = try await makeLoader(
            imagesByStore: [storeA: [imageA], storeB: []],
            pathsByImage: [imageA: "u/\(storeA)/photo.jpg"]
        )
        defer { session.invalidateAndCancel() }
        let pngData = samplePNGData()
        PhotoDownloadMockURLProtocol.reset { _ in (200, pngData) }
        defer { PhotoDownloadMockURLProtocol.clear() }

        await loader.load(storeIDs: [storeA, storeB])

        #expect(loader.photo(for: storeA) != nil)
        #expect(loader.photo(for: storeB) == nil)
    }

    @Test func concurrentLoadCallsForTheSameStoreOnlyFetchItOnce() async throws {
        let (loader, session) = try await makeLoader(
            imagesByStore: [storeA: [imageA]],
            pathsByImage: [imageA: "u/\(storeA)/photo.jpg"]
        )
        defer { session.invalidateAndCancel() }
        let pngData = samplePNGData()
        PhotoDownloadMockURLProtocol.reset { _ in (200, pngData) }
        defer { PhotoDownloadMockURLProtocol.clear() }

        // `load`は最初のフィルタリングをawaitより前に同期的に行うため、
        // 2回目の呼び出しが実際にスケジュールされる時点では1回目がすでにinFlightへ登録済みになる。
        async let first: Void = loader.load(storeIDs: [storeA])
        async let second: Void = loader.load(storeIDs: [storeA])
        _ = await (first, second)

        #expect(loader.photo(for: storeA) != nil)
        let listFetches = PhotoRepoMockURLProtocol.requests.filter {
            $0.url?.path == "/rest/v1/image" && query($0, "store_id") != nil
        }
        #expect(listFetches.count == 1)
    }

    // MARK: - Fixtures

    private func makeLoader(
        imagesByStore: [UUID: [UUID]],
        pathsByImage: [UUID: String] = [:],
        failImageList: Bool = false,
        failSigning: Bool = false
    ) async throws -> (StorePhotoLoader, URLSession) {
        let userID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let expiry = Date().timeIntervalSince1970 + 3600
        let auth = Data("""
        {"access_token":"test-access-token","token_type":"bearer","refresh_token":"test-refresh-token",
        "expires_in":3600,"expires_at":\(expiry),"user":{"id":"\(userID)","aud":"authenticated",
        "role":"authenticated","app_metadata":{},"user_metadata":{},
        "created_at":"2025-10-24T12:00:00Z","updated_at":"2025-10-24T12:00:00Z","is_anonymous":false}}
        """.utf8)

        PhotoRepoMockURLProtocol.reset { request in
            let route = request.url!.path
            if route == "/auth/v1/token" { return (200, auth) }
            let dbError = Data(#"{"code":"42501","message":"denied"}"#.utf8)
            let storageError = Data(#"{"statusCode":"403","message":"denied","error":"Unauthorized"}"#.utf8)

            if route == "/rest/v1/image" {
                if let storeIDQuery = query(request, "store_id") {
                    if failImageList { return (403, dbError) }
                    guard let id = UUID(uuidString: String(storeIDQuery.dropFirst(3))) else {
                        throw URLError(.badURL)
                    }
                    let imageIDs = imagesByStore[id] ?? []
                    let rows = imageIDs.map { imgID in
                        imageRow(id: imgID, storeID: id, path: pathsByImage[imgID] ?? "missing.jpg")
                    }
                    return (200, Data("[\(rows.joined(separator: ","))]".utf8))
                }
                if let imageIDQuery = query(request, "id") {
                    guard let imgID = UUID(uuidString: String(imageIDQuery.dropFirst(3))) else {
                        throw URLError(.badURL)
                    }
                    guard let path = pathsByImage[imgID] else { return (200, Data("[]".utf8)) }
                    let storeID = imagesByStore.first { $0.value.contains(imgID) }?.key ?? UUID()
                    return (200, Data("[\(imageRow(id: imgID, storeID: storeID, path: path))]".utf8))
                }
            }
            if route.hasPrefix("/storage/v1/object/sign/record-images/") {
                if failSigning { return (403, storageError) }
                let signedPath = String(route.dropFirst("/storage/v1/object/sign/record-images/".count))
                return (200, Data("{\"signedURL\":\"/object/sign/record-images/\(signedPath)?token=test\"}".utf8))
            }
            throw URLError(.unsupportedURL)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PhotoRepoMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://photo-loader-tests.invalid")!,
            supabaseKey: "test-anon-key",
            options: .init(
                auth: .init(storage: PhotoLoaderTestAuthStorage(), autoRefreshToken: false),
                global: .init(session: session)
            )
        )
        _ = try await client.auth.signIn(email: "test@example.com", password: "test-password")
        let repository = ImageRepository(client: client)
        return (StorePhotoLoader(repository: repository), session)
    }
}

private func samplePNGData() -> Data {
    let size = CGSize(width: 8, height: 8)
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { context in
        UIColor.systemOrange.setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
    return image.pngData()!
}

private func imageRow(id: UUID, storeID: UUID, path: String) -> String {
    "{\"id\":\"\(id)\",\"store_id\":\"\(storeID)\",\"image\":\"\(path)\",\"created_at\":\"2025-10-24T12:00:00.123456Z\"}"
}

private func query(_ request: URLRequest, _ name: String) -> String? {
    guard let url = request.url else { return nil }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
}

private final class PhotoLoaderTestAuthStorage: AuthLocalStorage, @unchecked Sendable {
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

/// `ImageRepository`に注入するSupabaseクライアントのセッションへ明示的に差し込むモック。
/// 画像一覧の取得・署名付きURLの発行（REST/Storage API）を横取りする。
private final class PhotoRepoMockURLProtocol: URLProtocol {
    private static let lock = NSLock()
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
            if request.url?.path != "/auth/v1/token" { Self.recordedRequests.append(request) }
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

/// `StorePhotoLoader`が写真バイト本体のダウンロードに直接使う`URLSession.shared`を横取りするための
/// グローバル登録用モック。`URLProtocol.registerClass`で有効化し、テストごとに必ず解除する。
private final class PhotoDownloadMockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?

    static func reset(handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler
        URLProtocol.registerClass(PhotoDownloadMockURLProtocol.self)
    }

    static func clear() {
        lock.lock(); defer { lock.unlock() }
        handler = nil
        URLProtocol.unregisterClass(PhotoDownloadMockURLProtocol.self)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            Self.lock.lock()
            let handler = Self.handler
            Self.lock.unlock()
            guard let handler else { throw URLError(.unsupportedURL) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
