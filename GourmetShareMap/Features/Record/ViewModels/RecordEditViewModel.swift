//
//  RecordEditViewModel.swift
//  GourmetShareMap
//

import Foundation
import Observation

@MainActor
@Observable
final class RecordEditViewModel {
    var name: String
    var category: String
    /// nilは「未評価」。DBのreputationはNULL許容で、保存入力は1〜5の整数。
    var rating: Int?
    var memo: String
    var repeatCount: Int

    private(set) var isSaving = false
    private(set) var errorMessage: String?

    private let store: MapStore
    private let repository: RecordRepository

    init(store: MapStore, repository: RecordRepository? = nil) {
        self.store = store
        self.repository = repository ?? RecordRepository()
        self.name = store.name
        self.category = store.category
        // 既存データには4.5のような小数評価もあるため、★の整数へ丸めて読み込む。
        self.rating = store.rating.map { max(1, min(5, Int($0.rounded()))) }
        self.memo = store.memo ?? ""
        // 保存入力は訪問回数1以上を要求する。0の行は1として読み込む。
        self.repeatCount = max(1, store.repeatCount)
    }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    /// 保存に成功したらtrueを返す。失敗時は`errorMessage`に理由を残す。
    func save() async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            // 保存は全項目の上書きのため、画面で編集しない座標とGoogle店舗IDも渡して既存値を保つ。
            _ = try await repository.saveStore(
                StoreSaveInput(
                    id: store.id,
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    category: category,
                    reputation: rating,
                    googlePlaceID: store.googlePlaceID,
                    memo: trimmedMemo.isEmpty ? nil : trimmedMemo,
                    repeatNum: repeatCount,
                    latitude: store.latitude,
                    longitude: store.longitude
                )
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
