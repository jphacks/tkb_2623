import Foundation
import Testing
@testable import GourmetShareMap

struct MascotLevelTests {
    @Test(arguments: [
        (0, MascotLevel.lv1), (1, .lv1), (5, .lv1),
        (6, .lv2), (12, .lv2), (20, .lv2),
        (21, .lv3), (22, .lv3), (500, .lv3),
    ])
    func levelBoundaries(storeCount: Int, expected: MascotLevel) {
        #expect(MascotLevel.forStoreCount(storeCount) == expected)
    }

    @Test func negativeStoreCountIsTreatedAsZero() {
        let progress = MascotProgress(storeCount: -3)
        #expect(progress.storeCount == 0)
        #expect(progress.level == .lv1)
    }

    @Test func remainingCountCountsDownToTheNextLevel() {
        #expect(MascotProgress(storeCount: 0).remainingToNextLevel == 6)
        #expect(MascotProgress(storeCount: 5).remainingToNextLevel == 1)
        #expect(MascotProgress(storeCount: 12).remainingToNextLevel == 9)
        #expect(MascotProgress(storeCount: 20).remainingToNextLevel == 1)
    }

    @Test func maxLevelHasNoNextLevel() {
        let progress = MascotProgress(storeCount: 25)
        #expect(progress.level.isMax)
        #expect(progress.nextLevel == nil)
        #expect(progress.remainingToNextLevel == nil)
        #expect(progress.fraction == 1)
        #expect(progress.progressText == "最大レベルに到達！")
    }

    @Test func fractionFillsEachLevelsOwnSpan() {
        #expect(MascotProgress(storeCount: 0).fraction == 0)
        // Lv.1 は 6 件で満タン。
        #expect(abs(MascotProgress(storeCount: 5).fraction - 5.0 / 6.0) < 0.0001)
        // Lv.2 は 6〜21 件の 15 件ぶんで満タン。
        #expect(MascotProgress(storeCount: 6).fraction == 0)
        #expect(abs(MascotProgress(storeCount: 13).fraction - 7.0 / 15.0) < 0.0001)
    }

    @Test func progressTextMarksTheFinalLevel() {
        #expect(MascotProgress(storeCount: 2).progressText == "あと 4 件で Lv.2")
        #expect(MascotProgress(storeCount: 13).progressText == "あと 8 件で Lv.3（最大）")
    }
}

struct MascotCharacterTests {
    @Test func frameImageNamesFollowTheAssetNamingRule() {
        let names = MascotCharacter.kometaro.frameImageNames
        #expect(names == (1...8).map { String(format: "kometaro_%02d", $0) })
        #expect(names.count == MascotCharacter.frameCount)
    }
}

struct MascotCharacterMappingTests {
    private func record(category: String?) -> StoreRecord {
        StoreRecord(
            id: UUID(), name: "test", category: category, reputation: nil,
            userID: UUID(), googlePlaceID: nil, memo: nil, repeatNum: 1,
            latitude: nil, longitude: nil, createdAt: .now
        )
    }

    @Test func lv1IsAlwaysMogumaruRegardlessOfCategory() {
        let records = Array(repeating: record(category: "和食"), count: 3)
        #expect(MascotCharacterMapping.character(records: records, level: .lv1) == .mogumaru)
    }

    @Test func lv2And3FollowTheDominantCategory() {
        let records = Array(repeating: record(category: "ラーメン・麺類"), count: 10)
        #expect(MascotCharacterMapping.character(records: records, level: .lv2) == .kometaro)
        #expect(MascotCharacterMapping.character(records: records, level: .lv3) == .ramenman)
    }

    @Test func dominantCategoryPicksTheHighestCount() {
        let records = Array(repeating: record(category: "スイーツ"), count: 3)
            + Array(repeating: record(category: "和食"), count: 1)
        #expect(MascotCharacterMapping.dominantCategory(in: records) == "スイーツ")
        #expect(MascotCharacterMapping.character(records: records, level: .lv3) == .cakechan)
    }

    @Test func tiesBreakByTheCanonicalCategoryOrder() {
        // 「和食」と「パン」が同数のときは、分類の並び順で早い「和食」を優先する。
        let records = [record(category: "パン"), record(category: "和食")]
        #expect(MascotCharacterMapping.dominantCategory(in: records) == "和食")
    }

    @Test func noRecordsOrUnknownCategoryFallsBackToSonota() {
        #expect(MascotCharacterMapping.dominantCategory(in: []) == "その他")
        #expect(MascotCharacterMapping.dominantCategory(in: [record(category: nil)]) == "その他")
        #expect(MascotCharacterMapping.character(for: "謎カテゴリ", level: .lv3) == .sakejiro)
    }
}

struct ModelStatsTests {
    @Test func accuracyPercentConvertsMeanAbsoluteError() {
        // 5段階（最大4のズレ）なので、MAE 0.8 は 80%。
        #expect(ModelStats(trainedRecordCount: 12, meanAbsoluteError: 0.8).accuracyPercent == 80)
        #expect(ModelStats(trainedRecordCount: 12, meanAbsoluteError: 0).accuracyPercent == 100)
        #expect(ModelStats(trainedRecordCount: 12, meanAbsoluteError: 4).accuracyPercent == 0)
        // ズレが4を超えても負の値にはしない。
        #expect(ModelStats(trainedRecordCount: 12, meanAbsoluteError: 5).accuracyPercent == 0)
    }

    @Test func accuracyPercentIsHiddenWhileTheApiDoesNotReportIt() {
        #expect(ModelStats(trainedRecordCount: 12, meanAbsoluteError: nil).accuracyPercent == nil)
    }
}
