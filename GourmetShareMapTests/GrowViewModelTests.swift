import Foundation
import Testing
@testable import GourmetShareMap

@MainActor
struct GrowViewModelTests {

    // MARK: - loadStats

    @Test func loadStatsPopulatesStatsOnSuccess() async throws {
        let stats = ModelStats(trainedRecordCount: 12, meanAbsoluteError: 0.5)
        let fake = FakeRecommendService(statsResult: .success(stats))
        let viewModel = GrowViewModel(service: fake)

        await viewModel.loadStats(records: [makeStore()])

        #expect(viewModel.stats == stats)
    }

    @Test func loadStatsSetsStatsToNilOnFailure() async throws {
        let fake = FakeRecommendService(
            statsResult: .success(ModelStats(trainedRecordCount: 1, meanAbsoluteError: 0.9))
        )
        let viewModel = GrowViewModel(service: fake)
        await viewModel.loadStats(records: [makeStore()])
        #expect(viewModel.stats != nil)

        fake.statsResult = .failure(FakeRecommendError())
        await viewModel.loadStats(records: [makeStore()])

        #expect(viewModel.stats == nil)
    }

    // MARK: - recommend

    @Test func recommendSuccessUpdatesRecommendationAndClearsRecommendingState() async throws {
        let recommendation = makeRecommendation()
        let fake = FakeRecommendService(recommendResult: .success(recommendation))
        let viewModel = GrowViewModel(service: fake)

        await viewModel.recommend(records: [makeStore()])

        #expect(viewModel.recommendation == recommendation)
        #expect(viewModel.recommendErrorMessage == nil)
        #expect(!viewModel.isRecommending)
    }

    @Test func recommendFailureSetsErrorMessageAndClearsRecommendingState() async throws {
        let fake = FakeRecommendService(recommendResult: .failure(RecommendError.notEnoughRecords))
        let viewModel = GrowViewModel(service: fake)

        await viewModel.recommend(records: [])

        #expect(viewModel.recommendation == nil)
        #expect(viewModel.recommendErrorMessage == RecommendError.notEnoughRecords.errorDescription)
        #expect(!viewModel.isRecommending)
    }

    @Test func recommendClearsPreviousErrorMessageOnRetrySuccess() async throws {
        let fake = FakeRecommendService(recommendResult: .failure(RecommendError.notEnoughRecords))
        let viewModel = GrowViewModel(service: fake)
        await viewModel.recommend(records: [])
        #expect(viewModel.recommendErrorMessage != nil)

        let recommendation = makeRecommendation()
        fake.recommendResult = .success(recommendation)
        await viewModel.recommend(records: [makeStore()])

        #expect(viewModel.recommendErrorMessage == nil)
        #expect(viewModel.recommendation == recommendation)
    }

    @Test func recommendIgnoresConcurrentCallsWhileAlreadyInFlight() async throws {
        let fake = FakeRecommendService(recommendResult: .success(makeRecommendation()))
        fake.pausesRecommend = true
        let viewModel = GrowViewModel(service: fake)

        let firstCall = Task { await viewModel.recommend(records: [makeStore()]) }
        // 1回目が service.recommend の中で止まり、isRecommending が true になるまで待つ。
        while !viewModel.isRecommending {
            await Task.yield()
        }

        // 1回目が進行中に呼んだ2回目は、何もせずそのまま戻るはず。
        await viewModel.recommend(records: [makeStore()])
        #expect(fake.recommendCallCount == 1)

        fake.resumeRecommend()
        await firstCall.value

        #expect(!viewModel.isRecommending)
        #expect(viewModel.recommendation != nil)
    }

    // MARK: - dismissRecommendation

    @Test func dismissRecommendationClearsRecommendation() async throws {
        let fake = FakeRecommendService(recommendResult: .success(makeRecommendation()))
        let viewModel = GrowViewModel(service: fake)
        await viewModel.recommend(records: [makeStore()])
        #expect(viewModel.recommendation != nil)

        viewModel.dismissRecommendation()

        #expect(viewModel.recommendation == nil)
    }

    // MARK: - progress

    @Test func progressReturnsMascotProgressMatchingStoreCount() {
        let viewModel = GrowViewModel(service: FakeRecommendService())

        #expect(viewModel.progress(storeCount: 7) == MascotProgress(storeCount: 7))
        #expect(viewModel.progress(storeCount: 0) == MascotProgress(storeCount: 0))
    }

    // MARK: - Helpers

    private func makeStore(
        name: String = "テスト店",
        category: String? = "ラーメン",
        reputation: Double? = 4
    ) -> StoreRecord {
        StoreRecord(
            id: UUID(), name: name, category: category, reputation: reputation,
            userID: UUID(), googlePlaceID: nil, memo: nil, repeatNum: 1,
            latitude: nil, longitude: nil, createdAt: Date()
        )
    }

    private func makeRecommendation() -> Recommendation {
        Recommendation(
            placeID: "place-1", name: "テスト食堂", category: "ラーメン",
            predictedRating: 4.5, reason: "テスト用の理由"
        )
    }
}

private struct FakeRecommendError: LocalizedError {
    var errorDescription: String? = "テスト用エラー"
}

/// RecommendServing は Sendable 要件があるため、可変状態は NSLock で保護する
/// (他のテストの `AuthLocalStorage` フェイクと同じ流儀)。
private final class FakeRecommendService: RecommendServing, @unchecked Sendable {
    private let lock = NSLock()

    var statsResult: Result<ModelStats, any Error> {
        get { lock.lock(); defer { lock.unlock() }; return _statsResult }
        set { lock.lock(); defer { lock.unlock() }; _statsResult = newValue }
    }
    var recommendResult: Result<Recommendation, any Error> {
        get { lock.lock(); defer { lock.unlock() }; return _recommendResult }
        set { lock.lock(); defer { lock.unlock() }; _recommendResult = newValue }
    }
    /// trueの間、recommend(from:) は resumeRecommend() が呼ばれるまで中断する。
    var pausesRecommend: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _pausesRecommend }
        set { lock.lock(); defer { lock.unlock() }; _pausesRecommend = newValue }
    }
    var recommendCallCount: Int {
        lock.lock(); defer { lock.unlock() }; return _recommendCallCount
    }
    var statsCallCount: Int {
        lock.lock(); defer { lock.unlock() }; return _statsCallCount
    }

    private var _statsResult: Result<ModelStats, any Error>
    private var _recommendResult: Result<Recommendation, any Error>
    private var _pausesRecommend = false
    private var _recommendCallCount = 0
    private var _statsCallCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    init(
        statsResult: Result<ModelStats, any Error> = .success(ModelStats(trainedRecordCount: 0, meanAbsoluteError: nil)),
        recommendResult: Result<Recommendation, any Error> = .failure(RecommendError.notEnoughRecords)
    ) {
        self._statsResult = statsResult
        self._recommendResult = recommendResult
    }

    func fetchModelStats(records: [StoreRecord]) async throws -> ModelStats {
        lock.lock()
        _statsCallCount += 1
        let result = _statsResult
        lock.unlock()
        return try result.get()
    }

    func recommend(from records: [StoreRecord]) async throws -> Recommendation {
        lock.lock()
        _recommendCallCount += 1
        let shouldPause = _pausesRecommend
        lock.unlock()

        if shouldPause {
            await withCheckedContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                lock.unlock()
            }
        }

        lock.lock()
        let result = _recommendResult
        lock.unlock()
        return try result.get()
    }

    /// pausesRecommend で止めた recommend(from:) を再開する。
    func resumeRecommend() {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }
}
