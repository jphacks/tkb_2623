//
//  GrowViewModel.swift
//  GourmetShareMap
//

import Foundation
import Observation

/// 育てる画面の状態。店舗数は `RecordStore` が持っているので、ここでは持たずに受け取る。
@MainActor
@Observable
final class GrowViewModel {
    private(set) var stats: ModelStats?
    private(set) var isRecommending = false
    private(set) var recommendation: Recommendation?
    /// レコメンドに失敗したときの表示用メッセージ。
    private(set) var recommendErrorMessage: String?

    private let service: any RecommendServing

    /// 引数を省略すると、APIが繋がるまでの仮実装を使う。
    init(service: (any RecommendServing)? = nil) {
        self.service = service ?? MockRecommendService()
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

    func recommend(records: [StoreRecord]) async {
        guard !isRecommending else { return }
        isRecommending = true
        recommendErrorMessage = nil
        do {
            recommendation = try await service.recommend(from: records)
        } catch {
            recommendErrorMessage = error.localizedDescription
        }
        isRecommending = false
    }

    func dismissRecommendation() {
        recommendation = nil
    }
}
