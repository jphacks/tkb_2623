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
            // 「焼肉・肉料理」のような長い分類名が縦に折り返されないようにする。
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            // 色は StoreCategoryStyle が13分類すべてを持つ。ここで分岐すると
            // ピンやカードと色がずれるため、単一の情報源から引く。
            .background(StoreCategoryStyle.color(for: category), in: Capsule())
    }
}

#Preview {
    HStack {
        CategoryBadge(category: "ラーメン・麺類")
        CategoryBadge(category: "洋食・西洋料理")
    }
    .padding()
}
