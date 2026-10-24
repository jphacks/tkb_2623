//
//  RecordViewModelTests.swift
//  GourmetShareMapTests
//

import CoreLocation
import Testing
@testable import GourmetShareMap

@MainActor
struct RecordViewModelTests {

    @Test func selectsNearestCandidateAfterSearch() async {
        let viewModel = RecordViewModel(storeSearchService: MockStoreSearchService())
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
        let viewModel = RecordViewModel(storeSearchService: MockStoreSearchService(returnsEmpty: true))
        await viewModel.search(for: .photo(latitude: 35.7282, longitude: 139.7608, takenAt: nil))

        guard case .loaded(let shops) = viewModel.searchState else {
            Issue.record("0 件はエラーではなく loaded([]) になるはず")
            return
        }
        #expect(shops.isEmpty)
        #expect(viewModel.selectedCandidate == nil)
        #expect(!viewModel.canSave)
    }

    @Test func searchOriginFallsBackToCurrentLocationWithoutPhotos() {
        let viewModel = RecordViewModel(storeSearchService: MockStoreSearchService())
        #expect(viewModel.searchOrigin == .currentLocation)
    }
}
