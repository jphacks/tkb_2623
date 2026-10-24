//
//  RecordCreateViewModel.swift
//  GourmetShareMap
//

import CoreLocation
import Observation
import UIKit

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
        case partiallyFailed(store: StoreRecord, failedPhotos: [RecordPhoto])
        case failed(message: String)
    }

    /// 保存に必須の入力項目（メモ以外）。
    enum Field: CaseIterable {
        case photos, store, category, rating

        var errorMessage: String {
            switch self {
            case .photos: "写真を1枚以上追加してください"
            case .store: "お店を選択してください"
            case .category: "カテゴリを選択してください"
            case .rating: "評価を選択してください"
            }
        }
    }

    /// 保存完了画面に出す内容。
    struct SavedSummary: Equatable {
        let storeName: String
        let category: String?
        let rating: Int
        let repeatNum: Int
        let photoCount: Int
        let coverImage: UIImage?
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
    /// 保存ボタンを押した後だけ、未入力の項目をエラー表示する。
    private(set) var showsValidationErrors = false
    /// 保存完了画面の表示用。閉じたら View 側で nil に戻す。
    var savedSummary: SavedSummary?

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

    /// 未入力の必須項目。
    var missingFields: [Field] {
        Field.allCases.filter { field in
            switch field {
            case .photos: photos.isEmpty
            case .store: selectedCandidate == nil
            // お店が未選択のときはお店のエラーだけ出す。
            case .category: selectedCandidate != nil && category == nil
            case .rating: rating == 0
            }
        }
    }

    /// 保存ボタンを押した後に表示する、その項目のエラー。
    func errorMessage(for field: Field) -> String? {
        showsValidationErrors && missingFields.contains(field) ? field.errorMessage : nil
    }

    /// 保存ボタンを押せるか（保存中・写真の再送待ちでないか）。未入力の項目があっても押せ、押すとエラーを表示する。
    var canSave: Bool {
        switch saveState {
        case .idle, .failed: true
        case .saving, .partiallyFailed: false
        }
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

    /// 保存する。未入力の必須項目があればエラーを表示して false を返す。
    @discardableResult
    func save(to recordStore: RecordStore) async -> Bool {
        guard canSave else { return false }
        guard missingFields.isEmpty, let shop = selectedCandidate, let category else {
            showsValidationErrors = true
            return false
        }
        let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = RecordDraft(
            shop: shop,
            category: category,
            reputation: rating,
            memo: trimmedMemo.isEmpty ? nil : trimmedMemo,
            photos: photos
        )

        saveState = .saving
        do {
            let result = try await recordStore.save(draft)
            if result.failedPhotos.isEmpty {
                finishSaving(store: result.store, failedCount: 0)
            } else {
                saveState = .partiallyFailed(store: result.store, failedPhotos: result.failedPhotos)
            }
        } catch {
            saveState = .failed(message: "保存できませんでした: \(error.localizedDescription)")
        }
        return true
    }

    /// アップロードに失敗した写真だけを再送する。
    func retryFailedUploads(to recordStore: RecordStore) async {
        guard case let .partiallyFailed(store, failedPhotos) = saveState else { return }
        saveState = .saving
        let stillFailed = await recordStore.retryUpload(failedPhotos, storeID: store.id)
        if stillFailed.isEmpty {
            finishSaving(store: store, failedCount: 0)
        } else {
            saveState = .partiallyFailed(store: store, failedPhotos: stillFailed)
        }
    }

    /// 写真の再送をあきらめて、記録だけ残した状態で終える。
    func discardFailedUploads() {
        guard case let .partiallyFailed(store, failedPhotos) = saveState else { return }
        finishSaving(store: store, failedCount: failedPhotos.count)
    }

    private func finishSaving(store: StoreRecord, failedCount: Int) {
        let summary = SavedSummary(
            storeName: store.name,
            category: store.category,
            rating: rating,
            repeatNum: store.repeatNum,
            photoCount: photos.count - failedCount,
            coverImage: photos.first?.image
        )
        reset()
        savedSummary = summary
    }

    /// 入力をすべて初期状態に戻す。
    func reset() {
        photos = []
        selectedCandidate = nil
        category = nil
        rating = 0
        memo = ""
        saveState = .idle
        showsValidationErrors = false
        searchState = .idle
        searchedCoordinate = nil
    }
}
