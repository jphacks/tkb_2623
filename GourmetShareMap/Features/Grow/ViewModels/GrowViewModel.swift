//
//  GrowViewModel.swift
//  GourmetShareMap
//

import CoreLocation
import Foundation
import Observation

/// 育てる画面の状態。店舗数は `RecordStore` が持っているので、ここでは持たずに受け取る。
@MainActor
@Observable
final class GrowViewModel {
    private(set) var stats: ModelStats?
    private(set) var isRecommending = false
    private(set) var recommendations: [Recommendation] = []
    /// レコメンドに失敗したときの表示用メッセージ。
    private(set) var recommendErrorMessage: String?

    private let service: any RecommendServing
    private let locationService: LocationService

    /// 引数を省略すると、実際のAIバックエンドに繋がる本番実装を使う。
    init(service: (any RecommendServing)? = nil, locationService: LocationService = LocationService()) {
        self.service = service ?? LiveRecommendService()
        self.locationService = locationService
    }

    func progress(storeCount: Int) -> MascotProgress {
        MascotProgress(storeCount: storeCount)
    }

    /// モデルの性能を取り直す。取得できなければ表示を伏せるだけで、画面は出し続ける。
    func loadStats(records: [StoreRecord]) async {
        do {
            stats = try await service.fetchModelStats(records: records)
        } catch {
            stats = nil
        }
    }

    /// `freeText`（「ラーメン食べたい」等）と現在地から、おすすめ上位3件を取りに行く。
    func recommend(freeText: String, records: [StoreRecord]) async {
        guard !isRecommending else { return }
        isRecommending = true
        recommendErrorMessage = nil
        recommendations = []
        do {
            let coordinate = try await locationService.currentCoordinate()
            recommendations = try await service.recommend(
                freeText: freeText, latitude: coordinate.latitude, longitude: coordinate.longitude, records: records
            )
            if recommendations.isEmpty {
                recommendErrorMessage = "近くに合うお店が見つかりませんでした。別の言葉で試してください。"
            }
        } catch {
            recommendErrorMessage = error.localizedDescription
        }
        isRecommending = false
    }

    func dismissRecommendations() {
        recommendations = []
    }
}
