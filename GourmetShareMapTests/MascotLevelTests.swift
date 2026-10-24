import Foundation
import Testing
@testable import GourmetShareMap

struct MascotLevelTests {
    @Test(arguments: [
        (0, MascotLevel.lv1), (1, .lv1), (4, .lv1),
        (5, .lv2), (12, .lv2), (19, .lv2),
        (20, .lv3), (21, .lv3), (500, .lv3),
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
        #expect(MascotProgress(storeCount: 0).remainingToNextLevel == 5)
        #expect(MascotProgress(storeCount: 4).remainingToNextLevel == 1)
        #expect(MascotProgress(storeCount: 12).remainingToNextLevel == 8)
        #expect(MascotProgress(storeCount: 19).remainingToNextLevel == 1)
    }

    @Test func maxLevelHasNoNextLevel() {
        let progress = MascotProgress(storeCount: 24)
        #expect(progress.level.isMax)
        #expect(progress.nextLevel == nil)
        #expect(progress.remainingToNextLevel == nil)
        #expect(progress.fraction == 1)
        #expect(progress.progressText == "最大レベルに到達！")
    }

    @Test func fractionFillsEachLevelsOwnSpan() {
        #expect(MascotProgress(storeCount: 0).fraction == 0)
        // Lv.1 は 5 件で満タン。
        #expect(abs(MascotProgress(storeCount: 4).fraction - 0.8) < 0.0001)
        // Lv.2 は 5〜20 件の 15 件ぶんで満タン。
        #expect(MascotProgress(storeCount: 5).fraction == 0)
        #expect(abs(MascotProgress(storeCount: 12).fraction - 7.0 / 15.0) < 0.0001)
    }

    @Test func progressTextMarksTheFinalLevel() {
        #expect(MascotProgress(storeCount: 2).progressText == "あと 3 件で Lv.2")
        #expect(MascotProgress(storeCount: 12).progressText == "あと 8 件で Lv.3（最大）")
    }

    @Test func frameImageNamesFollowTheAssetNamingRule() {
        let names = MascotLevel.lv2.frameImageNames
        #expect(names.first == "mascot_lv2_01")
        #expect(names.count == MascotLevel.maxFrameCount)
        #expect(names.allSatisfy { $0.hasPrefix("mascot_lv2_") })
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
