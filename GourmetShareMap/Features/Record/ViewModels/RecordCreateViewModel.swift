//
//  RecordCreateViewModel.swift
//  GourmetShareMap
//

import CoreLocation
import Observation

@Observable
final class RecordCreateViewModel {
    /// 店舗候補を検索する位置の決め方。
    enum SearchOrigin: Hashable {
        /// 写真の EXIF にある撮影位置
        case photo(latitude: Double, longitude: Double, takenAt: Date?)
        /// EXIF がないときの現在地フォールバック
        case currentLocation
    }

    enum SearchState {
        case idle
        case searching
        case loaded([NearbyShop])
        case failed(message: String, isPermissionDenied: Bool)
    }

    /// `.task(id:)` に渡すキー。位置が変わるか再検索が押されると検索し直す。
    struct SearchKey: Hashable {
        let origin: SearchOrigin?
        let attempt: Int
    }

    enum SaveState {
        case idle
        case saving
        /// 記録は保存できたが、一部の写真のアップロードに失敗した。
        case partiallyFailed(storeID: UUID, failedPhotos: [RecordPhoto])
        case failed(message: String)
    }

    /// カテゴリの選択肢（`PlaceCategoryClassifier` の分類名）。
    static let categories = PlaceCategoryClassifier.categoryRules.map(\.name)

    var photos: [RecordPhoto] = []
    var selectedCandidate: NearbyShop? {
        // 店を選び直したら、自動分類のカテゴリを初期値として入れ直す。
        didSet {
            if selectedCandidate != oldValue { category = selectedCandidate?.category }
        }
    }
    var category: String?
    var rating = 0
    var memo = ""

    private(set) var saveState: SaveState = .idle
    /// 保存完了のお知らせ表示用。表示したら View 側で nil に戻す。
    var savedMessage: String?

    private(set) var searchState: SearchState = .idle
    /// 直近の検索で使った座標。候補との距離表示に使う。
    private(set) var searchedCoordinate: CLLocationCoordinate2D?
    private var attempt = 0

    private let storeSearchService: any StoreSearchService
    private let locationService: LocationService

    init(
        storeSearchService: any StoreSearchService = PlacesStoreSearchService(),
        locationService: LocationService = LocationService()
    ) {
        self.storeSearchService = storeSearchService
        self.locationService = locationService
    }

    /// 並び順で最初に見つかった、位置情報付きの写真の撮影位置を使う（表紙を優先）。なければ現在地。
    /// 写真が 1 枚もないうちは検索しない（nil）。
    var searchOrigin: SearchOrigin? {
        guard !photos.isEmpty else { return nil }
        guard let photo = photos.first(where: { $0.location != nil }), let location = photo.location else {
            return .currentLocation
        }
        return .photo(latitude: location.latitude, longitude: location.longitude, takenAt: photo.takenAt)
    }

    var searchKey: SearchKey {
        SearchKey(origin: searchOrigin, attempt: attempt)
    }

    var canSave: Bool {
        guard !photos.isEmpty, selectedCandidate != nil, category != nil else { return false }
        if case .idle = saveState { return true }
        if case .failed = saveState { return true }
        return false
    }

    var isSaving: Bool {
        if case .saving = saveState { return true }
        return false
    }

    func retrySearch() {
        attempt += 1
    }

    func search(for origin: SearchOrigin?) async {
        guard let origin else {
            // 写真がすべて削除されたら候補もリセットする。
            searchState = .idle
            searchedCoordinate = nil
            selectedCandidate = nil
            return
        }
        searchState = .searching
        do {
            let coordinate: CLLocationCoordinate2D
            switch origin {
            case let .photo(latitude, longitude, _):
                coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            case .currentLocation:
                coordinate = try await locationService.currentCoordinate()
            }

            let candidates = try await storeSearchService.searchNearbyStores(around: coordinate)
            try Task.checkCancellation()

            searchedCoordinate = coordinate
            searchState = .loaded(candidates)
            // 前回選んだ店が新しい候補にも残っていれば選択を維持し、なければ一番近い候補を選んでおく。
            if selectedCandidate.map(candidates.contains) != true {
                selectedCandidate = candidates.first
            }
        } catch {
            // 位置が変わって新しい検索が始まった場合は、古い検索の結果を反映しない。
            guard !Task.isCancelled else { return }
            searchState = .failed(
                message: error.localizedDescription,
                isPermissionDenied: (error as? LocationServiceError) == .denied
            )
        }
    }

    func save(to recordStore: RecordStore) async {
        guard canSave, let shop = selectedCandidate, let category else { return }
        let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = RecordDraft(
            shop: shop,
            category: category,
            reputation: rating == 0 ? nil : rating,
            memo: trimmedMemo.isEmpty ? nil : trimmedMemo,
            photos: photos
        )

        saveState = .saving
        do {
            let result = try await recordStore.save(draft)
            if result.failedPhotos.isEmpty {
                finishSaving(storeName: result.store.name)
            } else {
                saveState = .partiallyFailed(storeID: result.store.id, failedPhotos: result.failedPhotos)
            }
        } catch {
            saveState = .failed(message: "保存できませんでした: \(error.localizedDescription)")
        }
    }

    /// アップロードに失敗した写真だけを再送する。
    func retryFailedUploads(to recordStore: RecordStore) async {
        guard case let .partiallyFailed(storeID, failedPhotos) = saveState, let shop = selectedCandidate else { return }
        saveState = .saving
        let stillFailed = await recordStore.retryUpload(failedPhotos, storeID: storeID)
        if stillFailed.isEmpty {
            finishSaving(storeName: shop.name)
        } else {
            saveState = .partiallyFailed(storeID: storeID, failedPhotos: stillFailed)
        }
    }

    /// 写真の再送をあきらめて、記録だけ残した状態で終える。
    func discardFailedUploads() {
        finishSaving(storeName: selectedCandidate?.name ?? "")
    }

    private func finishSaving(storeName: String) {
        reset()
        savedMessage = "「\(storeName)」を記録しました"
    }

    /// 入力をすべて初期状態に戻す。
    func reset() {
        photos = []
        selectedCandidate = nil
        category = nil
        rating = 0
        memo = ""
        saveState = .idle
        searchState = .idle
        searchedCoordinate = nil
    }
}
