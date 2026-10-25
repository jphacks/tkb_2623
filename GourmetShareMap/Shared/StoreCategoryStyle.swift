//
//  StoreCategoryStyle.swift
//  GourmetShareMap
//

import SwiftUI

/// `PlaceCategoryClassifier` の13分類に対応する表示スタイル。
///
/// 分類名はPlaces APIの判定結果がそのまま `store.category` に入るため、enumではなく文字列で引く。
/// 未知の分類(手入力やDB直編集)でも落とさず、「その他」と同じ見た目にフォールバックする。
enum StoreCategoryStyle {
    static func color(for category: String) -> Color {
        switch category {
        case "和食": Color(red: 0.45, green: 0.62, blue: 0.42)
        case "ラーメン・麺類": Color(red: 0.86, green: 0.42, blue: 0.24)
        case "焼肉・肉料理": Color(red: 0.70, green: 0.25, blue: 0.28)
        case "中華": Color(red: 0.80, green: 0.60, blue: 0.20)
        case "カレー": Color(red: 0.84, green: 0.55, blue: 0.16)
        case "アジア・エスニック": Color(red: 0.36, green: 0.58, blue: 0.47)
        case "洋食・西洋料理": Color(red: 0.33, green: 0.52, blue: 0.80)
        case "ファストフード・食堂": Color(red: 0.88, green: 0.48, blue: 0.36)
        case "カフェ・喫茶": Color(red: 0.56, green: 0.43, blue: 0.31)
        case "パン": Color(red: 0.76, green: 0.59, blue: 0.38)
        case "スイーツ": Color(red: 0.84, green: 0.47, blue: 0.60)
        case "居酒屋・バー": Color(red: 0.42, green: 0.38, blue: 0.62)
        default: Color(red: 0.49, green: 0.49, blue: 0.49)
        }
    }

    static func symbolName(for category: String) -> String {
        switch category {
        case "和食": "fish.fill"
        case "ラーメン・麺類": "takeoutbag.and.cup.and.straw.fill"
        case "焼肉・肉料理": "flame.fill"
        case "中華": "frying.pan.fill"
        case "カレー": "bowl.fill"
        case "アジア・エスニック": "leaf.fill"
        case "洋食・西洋料理": "fork.knife"
        case "ファストフード・食堂": "takeoutbag.and.cup.and.straw"
        case "カフェ・喫茶": "cup.and.saucer.fill"
        case "パン": "bag.fill"
        case "スイーツ": "birthday.cake.fill"
        case "居酒屋・バー": "wineglass.fill"
        default: "fork.knife"
        }
    }
}
