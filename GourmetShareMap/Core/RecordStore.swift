//
//  RecordStore.swift
//  GourmetShareMap
//

import Foundation
import Observation
import UIKit

/// 店舗記録の保存・取得（`RecordRepository`）。テストで差し替えられるようにプロトコルにしている。
protocol StoreRecordRepository {
    func fetchStores() async throws -> [StoreRecord]
    func saveStore(_ input: StoreSaveInput) async throws -> StoreRecord
}

/// 記録画像のアップロード（`ImageRepository`）。
protocol RecordImageUploading {
    func uploadImage(data: Data, storeID: UUID, format: RecordImageFormat) async throws -> ImageRecord
}

extension RecordRepository: StoreRecordRepository {}
extension ImageRepository: RecordImageUploading {}

/// 登録画面から渡す、保存する記録の内容。
struct RecordDraft {
    let shop: NearbyShop
    let category: String
    /// 1〜5。未評価は nil。
    let reputation: Int?
    let memo: String?
    /// 並び順どおりにアップロードする（先頭が表紙）。
    let photos: [RecordPhoto]
}

/// 保存結果。記録自体は保存できても、一部の写真のアップロードに失敗することがある。
struct RecordSaveResult {
    let store: StoreRecord
    let failedPhotos: [RecordPhoto]
}

/// 自分の店舗記録のキャッシュを一元管理する。保存後はここを更新し、マップ・プロフィールなど他画面に反映する。
@Observable
final class RecordStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// 自分の店舗記録（created_at 降順）。
    private(set) var records: [StoreRecord] = []
    private(set) var loadState: LoadState = .idle

    private let recordRepository: any StoreRecordRepository
    private let imageUploader: any RecordImageUploading

    /// 引数を省略すると Supabase に接続する本番の Repository を使う。
    init(
        recordRepository: (any StoreRecordRepository)? = nil,
        imageUploader: (any RecordImageUploading)? = nil
    ) {
        self.recordRepository = recordRepository ?? RecordRepository()
        self.imageUploader = imageUploader ?? ImageRepository()
    }

    func load() async {
        loadState = .loading
        do {
            records = try await recordRepository.fetchStores()
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// 同じお店（google_place_id）の既存の記録。
    func existingRecord(forPlaceID placeID: String) -> StoreRecord? {
        records.first { $0.googlePlaceID == placeID }
    }

    /// 記録を保存し、写真を表紙から順にアップロードする。
    /// 同じお店の記録が既にあれば、訪問回数を 1 増やして上書きし、写真はその記録に追加する。
    /// 店舗記録の保存に失敗したら throw する。写真の失敗は `failedPhotos` で返す。
    func save(_ draft: RecordDraft) async throws -> RecordSaveResult {
        // 再訪問の判定に既存の記録が必要なので、未取得なら先に取得する。
        if loadState != .loaded {
            records = try await recordRepository.fetchStores()
            loadState = .loaded
        }

        let existing = existingRecord(forPlaceID: draft.shop.placeID)
        let input = StoreSaveInput(
            id: existing?.id,
            name: draft.shop.name,
            category: draft.category,
            reputation: draft.reputation,
            googlePlaceID: draft.shop.placeID,
            memo: draft.memo,
            repeatNum: (existing?.repeatNum ?? 0) + 1,
            latitude: draft.shop.latitude,
            longitude: draft.shop.longitude
        )
        let store = try await recordRepository.saveStore(input)
        upsertCache(store)

        let failedPhotos = await upload(draft.photos, storeID: store.id)
        return RecordSaveResult(store: store, failedPhotos: failedPhotos)
    }

    /// アップロードに失敗した写真を再送する。まだ失敗した写真を返す。
    func retryUpload(_ photos: [RecordPhoto], storeID: UUID) async -> [RecordPhoto] {
        await upload(photos, storeID: storeID)
    }

    private func upload(_ photos: [RecordPhoto], storeID: UUID) async -> [RecordPhoto] {
        var failed: [RecordPhoto] = []
        // created_at の順に並ぶよう、1 枚ずつ順番にアップロードする。
        for photo in photos {
            do {
                guard let data = await photo.jpegData() else { throw ImageRepositoryError.emptyData }
                _ = try await imageUploader.uploadImage(data: data, storeID: storeID, format: .jpeg)
            } catch {
                failed.append(photo)
            }
        }
        return failed
    }

    private func upsertCache(_ store: StoreRecord) {
        records.removeAll { $0.id == store.id }
        records.insert(store, at: 0)
    }
}
