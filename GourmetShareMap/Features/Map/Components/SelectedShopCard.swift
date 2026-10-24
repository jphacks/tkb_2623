//
//  SelectedShopCard.swift
//  GourmetShareMap

import SwiftUI

struct SelectedShopCard: View {
    let shop: MapShop

    private let accentOrange = Color(red: 0.76, green: 0.35, blue: 0.22)

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(categoryColor.opacity(0.55))
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(.white)
                        .font(.system(size: 22))
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(shop.name)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.black)

                HStack(spacing: 8) {
                    CategoryBadge(category: shop.category)
                    StarRatingView(rating: shop.rating)
                }

                Text("リピート\(shop.repeatCount)回")
                    .font(.system(size: 12))
                    .foregroundStyle(.black.opacity(0.5))
            }

            Spacer(minLength: 0)

            Button {
                // TODO: 店舗編集画面ができたら遷移させる。
            } label: {
                Label("編集", systemImage: "pencil")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accentOrange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay {
                        Capsule().stroke(accentOrange, lineWidth: 1.5)
                    }
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 10, y: -2)
    }

    private var categoryColor: Color {
        switch shop.category {
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
    SelectedShopCard(shop: MapMockData.shops[0])
        .padding()
        .background(Color(red: 0.984, green: 0.968, blue: 0.937))
}
