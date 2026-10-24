//
//  CategoryBadge.swift
//  GourmetShareMap

import SwiftUI

/// 店舗ジャンルを表す丸ピル型バッジ。ジャンル文字列から表示色を決める。
struct CategoryBadge: View {
    let category: String

    var body: some View {
        Text(category)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color, in: Capsule())
    }

    private var color: Color {
        switch category {
        case "ラーメン": Color(red: 0.86, green: 0.42, blue: 0.24)
        case "洋食": Color(red: 0.33, green: 0.52, blue: 0.80)
        case "和食": Color(red: 0.45, green: 0.62, blue: 0.42)
        case "中華": Color(red: 0.80, green: 0.60, blue: 0.20)
        case "カフェ": Color(red: 0.56, green: 0.43, blue: 0.31)
        default: Color.gray
        }
    }
}

#Preview {
    HStack {
        CategoryBadge(category: "ラーメン")
        CategoryBadge(category: "洋食")
    }
    .padding()
}
