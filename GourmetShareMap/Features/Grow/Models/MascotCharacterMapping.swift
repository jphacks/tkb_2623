//
//  MascotCharacterMapping.swift
//  GourmetShareMap
//

import Foundation

/// 「一番多く登録しているカテゴリ」×「レベル」から見せるキャラを決める対応表。
/// Notion「AIキャラクター」の`categoryCharacters`仕様をそのまま反映している。
enum MascotCharacterMapping {
    private struct LevelSet {
        let lv1: MascotCharacter
        let lv2: MascotCharacter
        let lv3: MascotCharacter

        func character(for level: MascotLevel) -> MascotCharacter {
            switch level {
            case .lv1: lv1
            case .lv2: lv2
            case .lv3: lv3
            }
        }
    }

    // キーは `PlaceCategoryClassifier.categoryNames` と同じ13分類の文字列。
    private static let byCategory: [String: LevelSet] = [
        "和食": LevelSet(lv1: .mogumaru, lv2: .kometaro, lv3: .sushitaro),
        "ラーメン・麺類": LevelSet(lv1: .mogumaru, lv2: .kometaro, lv3: .ramenman),
        "焼肉・肉料理": LevelSet(lv1: .mogumaru, lv2: .kometaro, lv3: .sakejiro),
        "中華": LevelSet(lv1: .mogumaru, lv2: .kometaro, lv3: .ramenman),
        "カレー": LevelSet(lv1: .mogumaru, lv2: .kometaro, lv3: .pizaro),
        "アジア・エスニック": LevelSet(lv1: .mogumaru, lv2: .kometaro, lv3: .ramenman),
        "洋食・西洋料理": LevelSet(lv1: .mogumaru, lv2: .mugiro, lv3: .pizaro),
        "ファストフード・食堂": LevelSet(lv1: .mogumaru, lv2: .mugiro, lv3: .pizaro),
        "カフェ・喫茶": LevelSet(lv1: .mogumaru, lv2: .mugiro, lv3: .cakechan),
        "パン": LevelSet(lv1: .mogumaru, lv2: .mugiro, lv3: .cakechan),
        "スイーツ": LevelSet(lv1: .mogumaru, lv2: .mugiro, lv3: .cakechan),
        "居酒屋・バー": LevelSet(lv1: .mogumaru, lv2: .kometaro, lv3: .sakejiro),
        "その他": LevelSet(lv1: .mogumaru, lv2: .kometaro, lv3: .sakejiro),
    ]

    /// 指定カテゴリ・レベルのキャラ。未知のカテゴリは「その他」扱い。
    static func character(for category: String, level: MascotLevel) -> MascotCharacter {
        (byCategory[category] ?? byCategory["その他"]!).character(for: level)
    }

    /// 記録全体から、一番多く登録しているカテゴリのキャラを引く。
    static func character(records: [StoreRecord], level: MascotLevel) -> MascotCharacter {
        character(for: dominantCategory(in: records), level: level)
    }

    /// 一番多く登録しているカテゴリ。同数のときは `PlaceCategoryClassifier` の分類順（＝UIの絞り込み順）で
    /// 早いものを選び、画面を開くたびに表示が入れ替わらないようにする。カテゴリ未設定の記録は「その他」扱い。
    static func dominantCategory(in records: [StoreRecord]) -> String {
        var counts: [String: Int] = [:]
        for record in records {
            counts[record.category ?? "その他", default: 0] += 1
        }

        // 「その他」を基準値にしておくことで、記録が無い／どのカテゴリにも偏りが無いときに
        // 分類順の先頭（「和食」）へ引っ張られず、素直に「その他」へ落ちる。
        var best = "その他"
        var bestCount = counts["その他"] ?? 0
        for name in PlaceCategoryClassifier.categoryNames where name != "その他" {
            let count = counts[name] ?? 0
            if count > bestCount {
                bestCount = count
                best = name
            }
        }
        return best
    }
}
