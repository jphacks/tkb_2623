//
//  RecordViewModel.swift
//  GourmetShareMap
//

import CoreLocation
import Observation

@Observable
final class RecordViewModel {
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
        case loaded([StoreCandidate])
        case failed(message: String, isPermissionDenied: Bool)
    }

    /// `.task(id:)` に渡すキー。位置が変わるか再検索が押されると検索し直す。
    struct SearchKey: Hashable {
        let origin: SearchOrigin
        let attempt: Int
    }

    var photos: [RecordPhoto] = []
    var selectedCandidate: StoreCandidate?
    var rating = 0
    var memo = ""

    private(set) var searchState: SearchState = .idle
    /// 直近の検索で使った座標。候補との距離表示に使う。
    private(set) var searchedCoordinate: CLLocationCoordinate2D?
    private var attempt = 0

    private let storeSearchService: any StoreSearchService
    private let locationService: LocationService

    init(
        storeSearchService: any StoreSearchService = MockStoreSearchService(),
        locationService: LocationService = LocationService()
    ) {
        self.storeSearchService = storeSearchService
        self.locationService = locationService
    }

    /// 並び順で最初に見つかった、位置情報付きの写真の撮影位置を使う（表紙を優先）。なければ現在地。
    var searchOrigin: SearchOrigin {
        guard let photo = photos.first(where: { $0.location != nil }), let location = photo.location else {
            return .currentLocation
        }
        return .photo(latitude: location.latitude, longitude: location.longitude, takenAt: photo.takenAt)
    }

    var searchKey: SearchKey {
        SearchKey(origin: searchOrigin, attempt: attempt)
    }

    var canSave: Bool {
        !photos.isEmpty && selectedCandidate != nil
    }

    func retrySearch() {
        attempt += 1
    }

    func search(for origin: SearchOrigin) async {
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

    func save() {
        // TODO: 保存処理（Storage への画像アップロード・store / image への insert）は別 PR で実装する。
    }
}
