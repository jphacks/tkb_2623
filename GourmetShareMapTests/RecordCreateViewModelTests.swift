//
//  RecordCreateViewModelTests.swift
//  GourmetShareMapTests
//

import CoreLocation
import Testing
import UIKit
@testable import GourmetShareMap

@MainActor
struct RecordCreateViewModelTests {

    @Test func selectsNearestCandidateAfterSearch() async {
        let viewModel = RecordCreateViewModel(storeSearchService: MockStoreSearchService())
        await viewModel.search(for: .photo(latitude: 35.7282, longitude: 139.7608, takenAt: nil))

        guard case .loaded(let shops) = viewModel.searchState else {
            Issue.record("検索結果が loaded になっていない")
            return
        }
        #expect(!shops.isEmpty)
        #expect(viewModel.selectedCandidate == shops.first)
        #expect(viewModel.searchedCoordinate?.latitude == 35.7282)
    }

    @Test func emptyResultIsLoadedWithoutSelection() async {
        let viewModel = RecordCreateViewModel(storeSearchService: MockStoreSearchService(returnsEmpty: true))
        await viewModel.search(for: .photo(latitude: 35.7282, longitude: 139.7608, takenAt: nil))

        guard case .loaded(let shops) = viewModel.searchState else {
            Issue.record("0 件はエラーではなく loaded([]) になるはず")
            return
        }
        #expect(shops.isEmpty)
        #expect(viewModel.selectedCandidate == nil)
        #expect(viewModel.missingFields.contains(.store))
    }

    @Test func doesNotSearchUntilPhotoIsAdded() async {
        let viewModel = RecordCreateViewModel(storeSearchService: MockStoreSearchService())
        #expect(viewModel.searchOrigin == nil)

        await viewModel.search(for: viewModel.searchOrigin)
        guard case .idle = viewModel.searchState else {
            Issue.record("写真がないうちは検索せず idle のままのはず")
            return
        }
        #expect(viewModel.selectedCandidate == nil)
    }

    @Test func addPhotosStopsAtMaxCount() {
        let viewModel = RecordCreateViewModel(storeSearchService: MockStoreSearchService())
        viewModel.addPhotos((0..<8).map { _ in RecordTestData.photo() })
        viewModel.addPhotos((0..<5).map { _ in RecordTestData.photo() })
        #expect(viewModel.photos.count == RecordCreateViewModel.maxPhotoCount)
    }

    @Test func photoWithoutLocationFallsBackToCurrentLocation() {
        let viewModel = RecordCreateViewModel(storeSearchService: MockStoreSearchService())
        viewModel.photos = [RecordPhoto(image: UIImage(), location: nil, takenAt: nil)]
        #expect(viewModel.searchOrigin == .currentLocation)
    }
}

@MainActor
struct RecordCreateViewModelSaveTests {

    private func filledViewModel() -> RecordCreateViewModel {
        let viewModel = RecordCreateViewModel(storeSearchService: MockStoreSearchService())
        viewModel.photos = [RecordTestData.photo(), RecordTestData.photo()]
        viewModel.selectedCandidate = RecordTestData.shop
        viewModel.rating = 4
        viewModel.memo = "  おいしい  "
        return viewModel
    }

    @Test func selectingCandidateSetsCategoryFromClassification() {
        let viewModel = RecordCreateViewModel(storeSearchService: MockStoreSearchService())
        viewModel.selectedCandidate = RecordTestData.shop
        #expect(viewModel.category == "ラーメン・麺類")

        viewModel.category = "中華"
        #expect(viewModel.category == "中華")
    }

    @Test func successfulSaveResetsInputAndShowsMessage() async throws {
        let repository = FakeStoreRecordRepository()
        let recordStore = RecordStore(recordRepository: repository, imageUploader: FakeImageUploader())
        let viewModel = filledViewModel()
        viewModel.category = "中華"

        await viewModel.save(to: recordStore)

        let input = try #require(repository.savedInputs.first)
        #expect(input.category == "中華")
        #expect(input.memo == "おいしい")
        #expect(viewModel.photos.isEmpty)
        #expect(viewModel.selectedCandidate == nil)
        #expect(viewModel.rating == 0)
        #expect(viewModel.memo.isEmpty)
        #expect(viewModel.savedSummary != nil)
    }

    @Test func partialUploadFailureKeepsInputForRetry() async {
        let uploader = FakeImageUploader()
        uploader.failingCalls = [0]
        let recordStore = RecordStore(recordRepository: FakeStoreRecordRepository(), imageUploader: uploader)
        let viewModel = filledViewModel()

        await viewModel.save(to: recordStore)
        guard case let .partiallyFailed(_, failedPhotos) = viewModel.saveState else {
            Issue.record("一部失敗の状態になっていない")
            return
        }
        #expect(failedPhotos.count == 1)
        #expect(!viewModel.photos.isEmpty)

        await viewModel.retryFailedUploads(to: recordStore)
        #expect(viewModel.photos.isEmpty)
        #expect(viewModel.savedSummary != nil)
    }

    @Test func missingRequiredFieldsShowErrorsWithoutSaving() async {
        let repository = FakeStoreRecordRepository()
        let recordStore = RecordStore(recordRepository: repository, imageUploader: FakeImageUploader())
        let viewModel = RecordCreateViewModel(storeSearchService: MockStoreSearchService())
        viewModel.memo = "メモだけ"
        #expect(viewModel.errorMessage(for: .photos) == nil)

        let didStart = await viewModel.save(to: recordStore)

        #expect(!didStart)
        #expect(repository.savedInputs.isEmpty)
        #expect(viewModel.missingFields == [.photos, .store, .rating])
        #expect(viewModel.errorMessage(for: .photos) != nil)
        #expect(viewModel.errorMessage(for: .rating) != nil)

        // 入力した項目のエラーは消える。
        viewModel.rating = 3
        #expect(viewModel.errorMessage(for: .rating) == nil)
    }

    @Test func memoIsOptional() async throws {
        let repository = FakeStoreRecordRepository()
        let recordStore = RecordStore(recordRepository: repository, imageUploader: FakeImageUploader())
        let viewModel = filledViewModel()
        viewModel.memo = ""

        let didStart = await viewModel.save(to: recordStore)

        #expect(didStart)
        let input = try #require(repository.savedInputs.first)
        #expect(input.memo == nil)
        #expect(viewModel.savedSummary?.rating == 4)
        #expect(viewModel.savedSummary?.photoCount == 2)
        #expect(!viewModel.showsValidationErrors)
    }

    @Test func storeSaveFailureShowsErrorAndKeepsInput() async {
        let repository = FakeStoreRecordRepository()
        repository.saveError = URLError(.notConnectedToInternet)
        let recordStore = RecordStore(recordRepository: repository, imageUploader: FakeImageUploader())
        let viewModel = filledViewModel()

        await viewModel.save(to: recordStore)
        guard case .failed = viewModel.saveState else {
            Issue.record("保存失敗の状態になっていない")
            return
        }
        #expect(viewModel.photos.count == 2)
        #expect(viewModel.canSave)
    }
}
