import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Supabase
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

private struct CheckFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func check(_ condition: Bool, _ message: String) throws {
    guard condition else { throw CheckFailure(message: message) }
}

@main
struct NearbyStoreIntegrationCheck {
    @MainActor
    static func main() async {
        do { try await run() }
        catch {
            // Google側のエラーにキーが含まれていてもコンソールへ出さない。
            let message = error.localizedDescription
            let key = GoogleMapConfig.apiKey
            let redacted = key.isEmpty ? message : message.replacingOccurrences(of: key, with: "[REDACTED]")
            FileHandle.standardError.write(Data("結合テスト失敗: \(redacted)\n".utf8))
            exit(1)
        }
    }

    @MainActor
    private static func run() async throws {
        let env = ProcessInfo.processInfo.environment
        let mock = env["NEARBY_CHECK_MODE"] == "mock"
        guard let urlString = env["NEARBY_CHECK_REST_URL"], let url = URL(string: urlString),
              url.host == "127.0.0.1", let token = env["NEARBY_CHECK_JWT"],
              let latitude = Double(env["NEARBY_CHECK_LATITUDE"] ?? ""),
              let longitude = Double(env["NEARBY_CHECK_LONGITUDE"] ?? "") else {
            throw CheckFailure(message: "check_nearby_store_local.shから実行してください。")
        }
        let userID = UUID(uuidString: "c0240000-0000-4000-8000-000000000001")!
        let now = Date()
        let user = User(id: userID, appMetadata: [:], userMetadata: [:], aud: "authenticated",
                        createdAt: now, updatedAt: now)
        let authSession = Session(accessToken: token, tokenType: "bearer", expiresIn: 3600,
                                  expiresAt: now.timeIntervalSince1970 + 3600,
                                  refreshToken: "local-test-only", user: user)
        let storage = IntegrationAuthStorage()
        try storage.store(key: "nearby-check-session", value: JSONEncoder().encode(authSession))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IntegrationTransport.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = SupabaseClient(supabaseURL: url, supabaseKey: "local-test-only", options: .init(
            auth: .init(storage: storage, storageKey: "nearby-check-session", autoRefreshToken: false,
                        emitLocalSessionAsInitialSession: true),
            global: .init(session: session)
        ))
        let repository = RecordRepository(client: client)

        if mock {
            // 意図的に遠い店を先に置き、先頭ではなく最短距離の店舗を選ぶことを検証する。
            let latDirection = latitude >= 0 ? -1.0 : 1.0
            let lonDirection = longitude >= 0 ? -1.0 : 1.0
            IntegrationTransport.setGoogleResponse(status: 200, json: """
            {"places":[
              {"id":"fixture-far","displayName":{"text":"遠い食堂"},"location":{"latitude":\(latitude + latDirection * 0.004),"longitude":\(longitude + lonDirection * 0.004)},"primaryType":"japanese_restaurant"},
              {"id":"fixture-nearest","displayName":{"text":"最寄り喫茶"},"location":{"latitude":\(latitude + latDirection * 0.00005),"longitude":\(longitude + lonDirection * 0.00005)},"primaryType":"cafe"},
              {"id":"fixture-middle","displayName":{"text":"中距離食堂"},"location":{"latitude":\(latitude + latDirection * 0.001),"longitude":\(longitude + lonDirection * 0.001)},"primaryType":"restaurant"}
            ]}
            """)
        }
        let key = mock ? "fixture-key" : GoogleMapConfig.apiKey
        guard let result = try await searchAndSaveNearest(
            latitude: latitude, longitude: longitude, apiKey: key, session: session, repository: repository
        ) else {
            let rows: [StoreRecord] = try await client.from("store").select().execute().value
            try check(rows.isEmpty, "検索結果0件なのに店舗が保存されています。")
            throw CheckFailure(message: "半径1km以内に対象店舗がありません。保存は行っていません。別の座標で実行してください。")
        }
        let (shops, nearest, inserted) = result
        if mock { try check(nearest.placeID == "fixture-nearest", "最も近い店舗を選択できませんでした。") }
        print("検索件数: \(shops.count)")
        print("最寄り店舗: \(nearest.name) / \(nearest.placeID)")
        print("検索位置からの直線距離: \(String(format: "%.1f", distance(fromLatitude: latitude, longitude: longitude, to: nearest)))m")

        var input = StoreSaveInput(name: nearest.name, category: nearest.category,
                                   googlePlaceID: nearest.placeID, memo: "Nearby Search結合テスト",
                                   latitude: nearest.latitude, longitude: nearest.longitude)
        var rows = try await records(client: client, userID: userID, placeID: nearest.placeID)
        try check(rows.count == 1, "登録後の行数が1件ではありません。")
        let saved = rows[0]
        try check(saved.id == inserted.id && saved.userID == userID, "IDまたは所有者が不一致です。")
        try check(saved.name == nearest.name && saved.category == nearest.category, "店名・カテゴリが不一致です。")
        try check(saved.googlePlaceID == nearest.placeID, "Google店舗IDが不一致です。")
        try check(saved.latitude == nearest.latitude && saved.longitude == nearest.longitude, "店舗自体の座標が保存されていません。")
        try check(saved.memo == input.memo && saved.repeatNum == 1 && saved.reputation == nil, "初回の保存値が不正です。")

        // idを渡さず、検索した同じGoogle店舗の更新経路を通す。
        input.repeatNum = 2
        input.memo = nil
        let updated = try await repository.saveStore(input)
        rows = try await records(client: client, userID: userID, placeID: nearest.placeID)
        try check(rows.count == 1, "再保存で重複レコードが作成されました。")
        try check(updated.id == inserted.id && updated.createdAt == inserted.createdAt, "更新でIDまたは作成日時が変わりました。")
        try check(rows[0].repeatNum == 2 && rows[0].memo == nil, "再保存結果がDBに反映されていません。")

        if mock {
            // API結果0件とAPIエラー時には保存へ進まず、DBの件数が変わらないことを確認する。
            IntegrationTransport.setGoogleResponse(status: 200, json: "{\"places\":[]}")
            let empty = try await searchAndSaveNearest(latitude: latitude, longitude: longitude, apiKey: key,
                                                       session: session, repository: repository)
            try check(empty == nil, "0件レスポンスで保存処理へ進みました。")
            IntegrationTransport.setGoogleResponse(status: 403, json: "{\"error\":{\"message\":\"fixture denial\"}}")
            do {
                _ = try await searchAndSaveNearest(latitude: latitude, longitude: longitude, apiKey: key,
                                                   session: session, repository: repository)
                throw CheckFailure(message: "Google APIエラーがthrowされませんでした。")
            } catch NearbyShopError.api(let status, _) {
                try check(status == 403, "APIエラーのステータスが不一致です。")
            }
            let allRows: [StoreRecord] = try await client.from("store").select().execute().value
            try check(allRows.count == 1, "0件またはAPIエラーでDBの件数が変わりました。")
            print("0件・Google APIエラー時の非保存: OK")
        }
        print("成功: 最寄り店舗の検索 → RecordRepositoryで登録 → DBから再取得 → 同じ行の更新")
    }

    @MainActor
    private static func searchAndSaveNearest(
        latitude: Double, longitude: Double, apiKey: String, session: URLSession, repository: RecordRepository
    ) async throws -> ([NearbyShop], NearbyShop, StoreRecord)? {
        let shops = try await NearbyShopClient.findNearestShop(
            latitude: latitude, longitude: longitude, apiKey: apiKey, session: session
        )
        guard let nearest = shops.min(by: {
            distance(fromLatitude: latitude, longitude: longitude, to: $0)
                < distance(fromLatitude: latitude, longitude: longitude, to: $1)
        }) else { return nil }
        let saved = try await repository.saveStore(StoreSaveInput(
            name: nearest.name, category: nearest.category, googlePlaceID: nearest.placeID,
            memo: "Nearby Search結合テスト", latitude: nearest.latitude, longitude: nearest.longitude
        ))
        return (shops, nearest, saved)
    }

    @MainActor
    private static func records(client: SupabaseClient, userID: UUID, placeID: String) async throws -> [StoreRecord] {
        try await client.from("store").select().eq("user_id", value: userID)
            .eq("google_place_id", value: placeID).execute().value
    }

    private static func distance(fromLatitude latitude: Double, longitude: Double, to shop: NearbyShop) -> Double {
        let radians = Double.pi / 180
        let deltaLatitude = (shop.latitude - latitude) * radians
        let deltaLongitude = (shop.longitude - longitude) * radians
        let a = pow(sin(deltaLatitude / 2), 2)
            + cos(latitude * radians) * cos(shop.latitude * radians) * pow(sin(deltaLongitude / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, a))))
    }
}

private final class IntegrationAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.lock(); defer { lock.unlock() }; values[key] = value }
    func retrieve(key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func remove(key: String) throws { lock.lock(); defer { lock.unlock() }; values[key] = nil }
}

/// Supabase SDKの/rest/v1プレフィックスだけを外し、実PostgRESTへ転送する。
/// Googleはmockモードのときだけ固定レスポンスを返す。
private final class IntegrationTransport: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var googleResponse: (Int, Data)?
    private var forwardingTask: Task<Void, Never>?

    static func setGoogleResponse(status: Int, json: String) {
        lock.lock(); defer { lock.unlock() }
        googleResponse = (status, Data(json.utf8))
    }

    override class func canInit(with request: URLRequest) -> Bool {
        if request.url?.host == "127.0.0.1", request.url?.path.hasPrefix("/rest/v1/") == true { return true }
        lock.lock(); defer { lock.unlock() }
        return request.url?.host == "places.googleapis.com" && googleResponse != nil
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if request.url?.host == "places.googleapis.com" {
            do {
                let data = try Self.body(request)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                try check(json?["rankPreference"] as? String == "DISTANCE", "Nearby Searchの距離順指定がありません。")
                Self.lock.lock()
                let fixture = Self.googleResponse
                Self.lock.unlock()
                guard let (status, data) = fixture else { throw CheckFailure(message: "Google fixtureがありません。") }
                finish(data: data, response: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                                            headerFields: ["Content-Type": "application/json"])!)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
            return
        }
        forwardingTask = Task {
            do {
                var forwarded = request
                var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
                components.path = String(components.path.dropFirst("/rest/v1".count))
                forwarded.url = components.url
                if request.httpBody != nil || request.httpBodyStream != nil {
                    forwarded.httpBody = try Self.body(request)
                }
                let (data, response) = try await URLSession.shared.data(for: forwarded)
                finish(data: data, response: response)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() { forwardingTask?.cancel() }
    private func finish(data: Data, response: URLResponse) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    private static func body(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
