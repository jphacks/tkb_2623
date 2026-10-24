//
//  RecordStoreTests.swift
//  GourmetShareMapTests
//

import Foundation
import Testing
import UIKit
@testable import GourmetShareMap

@MainActor
final class FakeStoreRecordRepository: StoreRecordRepository {
    var stored: [StoreRecord] = []
    var saveError: (any Error)?
    private(set) var savedInputs: [StoreSaveInput] = []

    var currentUserID = UUID()

    func fetchStores() async throws -> [StoreRecord] { stored }

    func fetchVisibleStores() async throws -> VisibleStores {
        VisibleStores(currentUserID: currentUserID, stores: stored)
    }

    func saveStore(_ input: StoreSaveInput) async throws -> StoreRecord {
        if let saveError { throw saveError }
        savedInputs.append(input)
        let record = StoreRecord.make(
            id: input.id ?? UUID(), name: input.name, placeID: input.googlePlaceID, repeatNum: input.repeatNum
        )
        stored.removeAll { $0.id == record.id }
        stored.insert(record, at: 0)
        return record
    }
}

@MainActor
final class FakeImageUploader: RecordImageUploading {
    /// 何回目のアップロード（0 始まり）を失敗させるか。
    var failingCalls: Set<Int> = []
    private(set) var uploadedStoreIDs: [UUID] = []
    private var callCount = 0

    func uploadImage(data: Data, storeID: UUID, format: RecordImageFormat) async throws -> ImageRecord {
        defer { callCount += 1 }
        if failingCalls.contains(callCount) { throw URLError(.notConnectedToInternet) }
        uploadedStoreIDs.append(storeID)
        return ImageRecord(id: UUID(), storeID: storeID, path: "path", createdAt: .now)
    }
}

extension StoreRecord {
    static func make(id: UUID = UUID(), name: String = "麺屋 はる", placeID: String?, repeatNum: Int) -> StoreRecord {
        StoreRecord(
            id: id, name: name, category: "ラーメン・麺類", reputation: 4, userID: UUID(),
            googlePlaceID: placeID, memo: nil, repeatNum: repeatNum,
            latitude: 35.7, longitude: 139.7, createdAt: .now
        )
    }
}

@MainActor
enum RecordTestData {
    static let shop = NearbyShop(placeID: "place-1", name: "麺屋 はる", latitude: 35.7, longitude: 139.7, category: "ラーメン・麺類")

    static func photo() -> RecordPhoto {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return RecordPhoto(image: image, location: nil, takenAt: nil)
    }

    static func draft(photoCount: Int = 2) -> RecordDraft {
        RecordDraft(
            shop: shop, category: "ラーメン・麺類", reputation: 4, memo: "おいしい",
            photos: (0..<photoCount).map { _ in photo() }
        )
    }
}

@MainActor
struct RecordStoreTests {

    @Test func newStoreIsSavedWithFirstVisitAndAllPhotosUploaded() async throws {
        let repository = FakeStoreRecordRepository()
        let uploader = FakeImageUploader()
        let store = RecordStore(recordRepository: repository, imageUploader: uploader)

        let result = try await store.save(RecordTestData.draft(photoCount: 3))

        let input = try #require(repository.savedInputs.first)
        #expect(input.id == nil)
        #expect(input.repeatNum == 1)
        #expect(input.googlePlaceID == "place-1")
        #expect(input.reputation == 4)
        #expect(result.failedPhotos.isEmpty)
        #expect(uploader.uploadedStoreIDs == Array(repeating: result.store.id, count: 3))
        #expect(store.records.first?.id == result.store.id)
    }

    @Test func revisitIncrementsRepeatNumAndUpdatesExistingRecord() async throws {
        let existing = StoreRecord.make(placeID: "place-1", repeatNum: 2)
        let repository = FakeStoreRecordRepository()
        repository.stored = [existing]
        let store = RecordStore(recordRepository: repository, imageUploader: FakeImageUploader())
        await store.load()

        let result = try await store.save(RecordTestData.draft())

        let input = try #require(repository.savedInputs.first)
        #expect(input.id == existing.id)
        #expect(input.repeatNum == 3)
        #expect(store.records.count == 1)
        #expect(store.records.first?.repeatNum == 3)
        #expect(result.store.id == existing.id)
    }

    @Test func failedPhotosAreReturnedAndCanBeRetried() async throws {
        let uploader = FakeImageUploader()
        uploader.failingCalls = [1]
        let store = RecordStore(recordRepository: FakeStoreRecordRepository(), imageUploader: uploader)

        let result = try await store.save(RecordTestData.draft(photoCount: 3))
        #expect(result.failedPhotos.count == 1)

        let stillFailed = await store.retryUpload(result.failedPhotos, storeID: result.store.id)
        #expect(stillFailed.isEmpty)
        #expect(uploader.uploadedStoreIDs.count == 3)
    }

    @Test func storeSaveFailureThrowsWithoutUploading() async {
        let repository = FakeStoreRecordRepository()
        repository.saveError = StoreSaveError.invalidName
        let uploader = FakeImageUploader()
        let store = RecordStore(recordRepository: repository, imageUploader: uploader)

        await #expect(throws: StoreSaveError.invalidName) {
            try await store.save(RecordTestData.draft())
        }
        #expect(uploader.uploadedStoreIDs.isEmpty)
        #expect(store.records.isEmpty)
    }
}
