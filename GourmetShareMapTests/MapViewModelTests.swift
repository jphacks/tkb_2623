import Foundation
import Testing
@testable import GourmetShareMap

@MainActor
struct MapViewModelTests {
    private let me = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let friend = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private func makeRecord(
        id: UUID = UUID(),
        name: String = "店舗",
        category: String? = "カフェ",
        reputation: Double? = 4,
        userID: UUID,
        googlePlaceID: String? = nil,
        memo: String? = nil,
        repeatNum: Int = 1,
        latitude: Double? = 35.0,
        longitude: Double? = 139.0
    ) -> StoreRecord {
        StoreRecord(
            id: id, name: name, category: category, reputation: reputation,
            userID: userID, googlePlaceID: googlePlaceID, memo: memo,
            repeatNum: repeatNum, latitude: latitude, longitude: longitude,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeMapStore(
        id: UUID = UUID(),
        category: String = "カフェ",
        isMine: Bool = true,
        sharedWithFriend: Bool = false
    ) -> MapStore {
        MapStore(
            id: id, name: "店舗", category: category, rating: nil, repeatCount: 1, memo: nil,
            googlePlaceID: nil, latitude: 35.0, longitude: 139.0,
            isMine: isMine, sharedWithFriend: sharedWithFriend
        )
    }

    // MARK: - stores(from:)

    @Test func nilVisibleStoresReturnsEmptyArray() {
        let viewModel = MapViewModel()
        #expect(viewModel.stores(from: nil).isEmpty)
    }

    @Test func storesWithoutCoordinatesAreExcluded() {
        let withCoordinate = makeRecord(userID: me)
        let missingLatitude = makeRecord(userID: me, latitude: nil)
        let missingLongitude = makeRecord(userID: me, longitude: nil)
        let visible = VisibleStores(currentUserID: me, stores: [withCoordinate, missingLatitude, missingLongitude])
        let viewModel = MapViewModel()

        let stores = viewModel.stores(from: visible)

        #expect(stores.map(\.id) == [withCoordinate.id])
    }

    @Test func categoryDefaultsToOtherWhenNil() {
        let record = makeRecord(category: nil, userID: me)
        let visible = VisibleStores(currentUserID: me, stores: [record])
        let viewModel = MapViewModel()

        #expect(viewModel.stores(from: visible).first?.category == "その他")
    }

    @Test func isMineReflectsWhetherTheRecordBelongsToTheCurrentUser() {
        let mine = makeRecord(userID: me)
        let theirs = makeRecord(userID: friend)
        let visible = VisibleStores(currentUserID: me, stores: [mine, theirs])
        let viewModel = MapViewModel()

        let stores = viewModel.stores(from: visible)

        #expect(stores.first { $0.id == mine.id }?.isMine == true)
        #expect(stores.first { $0.id == theirs.id }?.isMine == false)
    }

    @Test func sharedWithFriendIsTrueOnlyWhenBothSidesRegisteredTheSamePlace() {
        let shared = "place-shared"
        let mineOnly = "place-mine-only"
        let friendOnly = "place-friend-only"
        let records = [
            makeRecord(userID: me, googlePlaceID: shared),
            makeRecord(userID: friend, googlePlaceID: shared),
            makeRecord(userID: me, googlePlaceID: mineOnly),
            makeRecord(userID: friend, googlePlaceID: friendOnly),
            makeRecord(userID: me, googlePlaceID: nil),
        ]
        let visible = VisibleStores(currentUserID: me, stores: records)
        let viewModel = MapViewModel()

        let stores = viewModel.stores(from: visible)

        #expect(stores.filter { $0.googlePlaceID == shared }.allSatisfy { $0.sharedWithFriend })
        #expect(stores.first { $0.googlePlaceID == mineOnly }?.sharedWithFriend == false)
        #expect(stores.first { $0.googlePlaceID == friendOnly }?.sharedWithFriend == false)
        #expect(stores.first { $0.googlePlaceID == nil }?.sharedWithFriend == false)
    }

    // MARK: - filtered

    @Test func filteredAppliesTheSelectedCategoryFilter() {
        let viewModel = MapViewModel()
        let ramen = makeMapStore(category: "ラーメン")
        let cafe = makeMapStore(category: "カフェ")

        viewModel.selectedCategory = .all
        #expect(viewModel.filtered([ramen, cafe]) == [ramen, cafe])

        viewModel.selectedCategory = .category("ラーメン")
        #expect(viewModel.filtered([ramen, cafe]) == [ramen])
    }

    @Test func filteredAppliesTheOwnerFilter() {
        let viewModel = MapViewModel()
        let mine = makeMapStore(isMine: true)
        let theirs = makeMapStore(isMine: false)

        viewModel.ownerFilter = .both
        #expect(viewModel.filtered([mine, theirs]) == [mine, theirs])

        viewModel.ownerFilter = .me
        #expect(viewModel.filtered([mine, theirs]) == [mine])

        viewModel.ownerFilter = .friend
        #expect(viewModel.filtered([mine, theirs]) == [theirs])
    }

    @Test func filteredCombinesCategoryAndOwnerFilters() {
        let viewModel = MapViewModel()
        let mineRamen = makeMapStore(category: "ラーメン", isMine: true)
        let friendRamen = makeMapStore(category: "ラーメン", isMine: false)
        let mineCafe = makeMapStore(category: "カフェ", isMine: true)

        viewModel.selectedCategory = .category("ラーメン")
        viewModel.ownerFilter = .me

        #expect(viewModel.filtered([mineRamen, friendRamen, mineCafe]) == [mineRamen])
    }

    // MARK: - selection

    @Test func selectedStoreIsNilWhenNothingIsSelected() {
        let viewModel = MapViewModel()
        let store = makeMapStore()

        #expect(viewModel.selectedStoreID == nil)
        #expect(viewModel.selectedStore(in: [store]) == nil)
    }

    @Test func selectStoresTheIDAndSelectedStoreLooksItUp() {
        let viewModel = MapViewModel()
        let store = makeMapStore()
        let other = makeMapStore()

        viewModel.select(storeID: store.id)

        #expect(viewModel.selectedStoreID == store.id)
        #expect(viewModel.selectedStore(in: [store, other]) == store)
    }

    @Test func selectedStoreIsNilWhenTheSelectedIDIsNoLongerInTheList() {
        let viewModel = MapViewModel()
        let store = makeMapStore()

        viewModel.select(storeID: UUID())

        #expect(viewModel.selectedStore(in: [store]) == nil)
    }

    @Test func selectingNilClearsTheSelection() {
        let viewModel = MapViewModel()
        let store = makeMapStore()
        viewModel.select(storeID: store.id)

        viewModel.select(storeID: nil)

        #expect(viewModel.selectedStoreID == nil)
        #expect(viewModel.selectedStore(in: [store]) == nil)
    }
}
