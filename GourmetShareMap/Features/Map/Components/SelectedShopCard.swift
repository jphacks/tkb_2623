//
//  SelectedShopCard.swift
//  GourmetShareMap

import SwiftUI

struct SelectedShopCard: View {
    let store: MapStore
    let onEdit: () -> Void

    private let accentOrange = Color(red: 0.76, green: 0.35, blue: 0.22)

    var body: some View {
        HStack(spacing: 14) {
            StorePhotoThumbnail(storeID: store.id, category: store.category)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(store.name)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(.black)
                        .lineLimit(1)

                    if !store.isMine {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(accentOrange)
                    }
                }

                HStack(spacing: 8) {
                    CategoryBadge(category: store.category)
                    if let rating = store.rating {
                        StarRatingView(rating: rating)
                    } else {
                        Text("未評価")
                            .font(.system(size: 12))
                            .foregroundStyle(.black.opacity(0.4))
                    }
                }
                // 横幅が足りないときに縦へ折り返させない。カテゴリ名は1行で出す。
                .fixedSize(horizontal: false, vertical: true)

                Text("リピート\(store.repeatCount)回")
                    .font(.system(size: 12))
                    .foregroundStyle(.black.opacity(0.5))

                if let memo = store.memo, !memo.isEmpty {
                    Text(memo)
                        .font(.system(size: 12))
                        .foregroundStyle(.black.opacity(0.65))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: 0)

            // 自分の記録だけ編集できる。フレンドの記録はRLSで更新できないためボタンを出さない。
            if store.isMine {
                Button(action: onEdit) {
                    Label("編集", systemImage: "pencil")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accentOrange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay {
                            Capsule().stroke(accentOrange, lineWidth: 1.5)
                        }
                }
                // 店舗名やメモが長くてもボタンが潰れないようにする。
                .fixedSize()
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 10, y: -2)
    }
}

#Preview {
    SelectedShopCard(
        store: MapStore(
            id: UUID(),
            name: "麺屋 はる",
            category: "ラーメン・麺類",
            rating: 4,
            repeatCount: 3,
            memo: "夕やけだんだん側。昼は満席になりやすい。",
            googlePlaceID: nil,
            latitude: 35.7205,
            longitude: 139.7658,
            isMine: true,
            sharedWithFriend: true
        ),
        onEdit: {}
    )
    .padding()
    .background(Color(red: 0.984, green: 0.968, blue: 0.937))
}
