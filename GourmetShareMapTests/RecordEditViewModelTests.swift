//
//  RecordEditViewModelTests.swift
//  GourmetShareMapTests
//

import CoreLocation
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
struct RecordEditViewModelTests {
    private let userID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let storeID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    // MARK: - 初期値の変換

    @Test(arguments: [
        (nil as Double?, nil as Int?),
        (4.5, 5),   // 四捨五入(away from zero)で5へ
        (4.4, 4),   // 四捨五入で4のまま
        (0.2, 1),   // 四捨五入で0になった後、下限1にクランプ
        (5.6, 5),   // 四捨五入で6になった後、上限5にクランプ
        (1.0, 1),
        (5.0, 5),
    ])
    func ratingIsRoundedAndClampedWhenLoadingFromStore(rawRating: Double?, expected: Int?) {
        let viewModel = RecordEditViewModel(store: makeStore(rating: rawRating), repository: dummyRepository())
        #expect(viewModel.rating == expected)
    }

    @Test(arguments: [(0, 1), (1, 1), (5, 5)])
    func repeatCountHasLowerBoundOfOneWhenLoadingFromStore(rawCount: Int, expected: Int) {
        let viewModel = RecordEditViewModel(store: makeStore(repeatCount: rawCount), repository: dummyRepository())
        #expect(viewModel.repeatCount == expected)
    }

    @Test func nameCategoryAndMemoAreCopiedFromStoreAndNilMemoBecomesEmptyString() {
        let store = makeStore(name: "喫茶店", category: "カフェ・喫茶", memo: nil)
        let viewModel = RecordEditViewModel(store: store, repository: dummyRepository())
        #expect(viewModel.name == "喫茶店")
        #expect(viewModel.category == "カフェ・喫茶")
        #expect(viewModel.memo == "")
    }

    // MARK: - canSave

    @Test(arguments: ["", "   ", "\n\t"])
    func canSaveIsFalseWhenNameIsEmptyOrWhitespace(name: String) {
        let viewModel = RecordEditViewModel(store: makeStore(), repository: dummyRepository())
        viewModel.name = name
        #expect(viewModel.canSave == false)
    }

    @Test func canSaveIsTrueWhenNameIsNonEmptyAndNotSaving() {
        let viewModel = RecordEditViewModel(store: makeStore(), repository: dummyRepository())
        viewModel.name = "新しい店名"
        #expect(viewModel.canSave == true)
    }

    @Test func canSaveIsFalseWhileSaveIsInFlightAndTrueAgainAfterCompletion() async throws {
        let gate = DispatchSemaphore(value: 0)
        let (repository, session) = try await makeRepository(gate: gate)
        defer { session.invalidateAndCancel() }
        let viewModel = RecordEditViewModel(store: makeStore(), repository: repository)
        viewModel.name = "有効な店名"

        let task = Task { await viewModel.save() }
        // save()がisSavingをtrueにしてネットワーク呼び出し(gateでブロック中)へ進むまでMainActorの番を譲る。
        var iterations = 0
        while !viewModel.isSaving, iterations < 1000 {
            await Task.yield()
            iterations += 1
        }
        #expect(viewModel.isSaving == true)
        #expect(viewModel.canSave == false)

        gate.signal()
        let result = await task.value
        #expect(result == true)
        #expect(viewModel.isSaving == false)
        #expect(viewModel.canSave == true)
    }

    // MARK: - save()成功時

    @Test func saveSendsEditedFieldsAndPreservesUneditedCoordinatesAndPlaceID() async throws {
        let store = makeStore(
            id: storeID, name: "元の店名", category: "ラーメン・麺類", rating: 3, repeatCount: 2,
            memo: "元のメモ", googlePlaceID: "place-xyz", latitude: 35.6812, longitude: 139.7671
        )
        let (repository, session) = try await makeRepository()
        defer { session.invalidateAndCancel() }
        let viewModel = RecordEditViewModel(store: store, repository: repository)
        viewModel.name = " 新しい店名 \n"
        viewModel.category = "カフェ・喫茶"
        viewModel.rating = 5
        viewModel.memo = "  とても良かった  "
        viewModel.repeatCount = 4

        let result = await viewModel.save()

        #expect(result == true)
        let request = try #require(RecordEditMockURLProtocol.requests.last)
        #expect(request.httpMethod == "PATCH")
        // 更新対象の行はIDで特定される(bodyにはidを含めない仕様のため、クエリ側で検証する)。
        #expect(query(request, "id")?.lowercased() == "eq.\(storeID.uuidString.lowercased())")
        let body = try body(request)
        #expect(body["id"] == nil)
        #expect(body["name"] as? String == "新しい店名")
        #expect(body["category"] as? String == "カフェ・喫茶")
        #expect(body["reputation"] as? Int == 5)
        // 座標とGoogle店舗IDは画面で編集しないが、既存値を保つために送信される。
        #expect(body["google_place_id"] as? String == "place-xyz")
        #expect(body["memo"] as? String == "とても良かった")
        #expect(body["repeat_num"] as? Int == 4)
        #expect(body["latitude"] as? Double == 35.6812)
        #expect(body["longitude"] as? Double == 139.7671)
    }

    @Test func saveTrimsMemoToNilWhenBlank() async throws {
        let (repository, session) = try await makeRepository()
        defer { session.invalidateAndCancel() }
        let viewModel = RecordEditViewModel(store: makeStore(), repository: repository)
        viewModel.memo = "   \n\t  "

        let result = await viewModel.save()

        #expect(result == true)
        let body = try body(try #require(RecordEditMockURLProtocol.requests.last))
        #expect(body["memo"] is NSNull)
    }

    // MARK: - save()失敗時

    @Test func saveSetsErrorMessageAndReturnsFalseOnFailure() async throws {
        let (repository, session) = try await makeRepository(networkError: true)
        defer { session.invalidateAndCancel() }
        let viewModel = RecordEditViewModel(store: makeStore(), repository: repository)

        let result = await viewModel.save()

        #expect(result == false)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.isSaving == false)
    }

    // MARK: - テスト用ヘルパー

    private func makeStore(
        id: UUID = UUID(), name: String = "テスト食堂", category: String = "ラーメン・麺類",
        rating: Double? = 4, repeatCount: Int = 2, memo: String? = "おいしい",
        googlePlaceID: String? = "place-xyz", latitude: Double = 35.0, longitude: Double = 139.0,
        isMine: Bool = true, sharedWithFriend: Bool = false
    ) -> MapStore {
        MapStore(
            id: id, name: name, category: category, rating: rating, repeatCount: repeatCount,
            memo: memo, googlePlaceID: googlePlaceID, latitude: latitude, longitude: longitude,
            isMine: isMine, sharedWithFriend: sharedWithFriend
        )
    }

    /// ネットワークに触れない初期値・canSaveのテスト用に、ダミーのクライアントだけを持つRepositoryを用意する。
    private func dummyRepository() -> RecordRepository {
        RecordRepository(client: SupabaseClient(
            supabaseURL: URL(string: "https://record-edit-tests.invalid")!, supabaseKey: "dummy-anon-key"
        ))
    }

    private func recordJSON() -> String {
        """
        {"id":"\(storeID)","name":"テスト食堂","category":"ラーメン・麺類","reputation":4,
        "user_id":"\(userID)","google_place_id":"place-xyz","memo":"おいしい",
        "repeat_num":2,"latitude":35,"longitude":139,"created_at":"2025-10-24T12:00:00.123456+00:00"}
        """
    }

    private func makeRepository(
        status: Int = 200, response: Data? = nil, networkError: Bool = false, gate: DispatchSemaphore? = nil
    ) async throws -> (RecordRepository, URLSession) {
        let record = response ?? Data(recordJSON().utf8)
        let expiry = Date().timeIntervalSince1970 + 3600
        let auth = Data("""
        {"access_token":"test-access-token","token_type":"bearer","refresh_token":"test-refresh-token",
        "expires_in":3600,"expires_at":\(expiry),"user":{"id":"\(userID)","aud":"authenticated",
        "role":"authenticated","app_metadata":{},"user_metadata":{},
        "created_at":"2025-10-24T12:00:00Z","updated_at":"2025-10-24T12:00:00Z","is_anonymous":false}}
        """.utf8)
        RecordEditMockURLProtocol.reset { request in
            if request.url?.path == "/auth/v1/token" { return (200, auth) }
            guard request.url?.path == "/rest/v1/store" else { throw URLError(.unsupportedURL) }
            if networkError { throw URLError(.notConnectedToInternet) }
            gate?.wait()
            // RecordEditViewModelは常にstore.idを渡すため、保存は常にPATCH(更新)になる。
            if request.httpMethod == "PATCH", status == 200, response == nil {
                return (200, Data("[\(String(decoding: record, as: UTF8.self))]".utf8))
            }
            return (status, record)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordEditMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://record-edit-tests.invalid")!, supabaseKey: "test-anon-key",
            options: .init(auth: .init(storage: RecordEditTestAuthStorage(), autoRefreshToken: false),
                           global: .init(session: session))
        )
        _ = try await client.auth.signIn(email: "test@example.com", password: "test-password")
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

private final class RecordEditTestAuthStorage: AuthLocalStorage, @unchecked Sendable {
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

private final class RecordEditMockURLProtocol: URLProtocol {
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
