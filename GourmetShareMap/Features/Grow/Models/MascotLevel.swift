//
//  MascotLevel.swift
//  GourmetShareMap
//

import Foundation

/// まんぷく先生の成長段階。登録した店舗数（= AIの学習データ数）で決まる。
/// 境界は 0〜4件 / 5〜19件 / 20件以上 の3段階で、Lv.3 が最大。
enum MascotLevel: Int, CaseIterable, Identifiable, Sendable {
    case lv1 = 1
    case lv2 = 2
    case lv3 = 3

    var id: Int { rawValue }

    /// このレベルになるのに必要な登録店舗数。
    var requiredStoreCount: Int {
        switch self {
        case .lv1: 0
        case .lv2: 5
        case .lv3: 20
        }
    }

    var name: String {
        switch self {
        case .lv1: "ごはんつぶ"
        case .lv2: "みならいコック"
        case .lv3: "まんぷく先生"
        }
    }

    /// 「Lv.2 みならいコック」。
    var title: String { "Lv.\(rawValue) \(name)" }

    var isMax: Bool { self == .lv3 }

    var next: MascotLevel? { MascotLevel(rawValue: rawValue + 1) }

    /// 届いたキャラクター画像を入れるAsset名。この順にコマ送りしてループする。
    /// 枚数は決め打ちせずAssetに入っている分だけ使うので、後から増減できる。
    /// 予定は Lv.1に2枚・Lv.2に3枚・Lv.3に3枚（計8枚）。
    var frameImageNames: [String] {
        (1...Self.maxFrameCount).map { String(format: "mascot_lv%d_%02d", rawValue, $0) }
    }

    /// 1レベルあたり探すコマ数の上限。実際に使うのはAssetに存在する分だけ。
    static let maxFrameCount = 6

    static func forStoreCount(_ count: Int) -> MascotLevel {
        if count >= MascotLevel.lv3.requiredStoreCount { return .lv3 }
        if count >= MascotLevel.lv2.requiredStoreCount { return .lv2 }
        return .lv1
    }
}

/// 現在のレベルと、次のレベルまでの進み具合。
struct MascotProgress: Equatable, Sendable {
    let storeCount: Int
    let level: MascotLevel

    init(storeCount: Int) {
        self.storeCount = max(0, storeCount)
        self.level = MascotLevel.forStoreCount(self.storeCount)
    }

    var nextLevel: MascotLevel? { level.next }

    /// 次のレベルまでの残り件数。最大レベルなら nil。
    var remainingToNextLevel: Int? {
        guard let next = nextLevel else { return nil }
        return max(0, next.requiredStoreCount - storeCount)
    }

    /// 次のレベルまでの進捗（0〜1）。最大レベルは満タン。
    var fraction: Double {
        guard let next = nextLevel else { return 1 }
        let span = Double(next.requiredStoreCount - level.requiredStoreCount)
        guard span > 0 else { return 1 }
        let done = Double(storeCount - level.requiredStoreCount)
        return min(1, max(0, done / span))
    }

    /// 「あと8件で Lv.3（最大）」／最大レベルなら到達の表示。
    var progressText: String {
        guard let next = nextLevel, let remaining = remainingToNextLevel else {
            return "最大レベルに到達！"
        }
        let suffix = next.isMax ? "（最大）" : ""
        return "あと \(remaining) 件で Lv.\(next.rawValue)\(suffix)"
    }
}
