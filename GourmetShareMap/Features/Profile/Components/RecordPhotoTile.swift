//
//  RecordPhotoTile.swift
//  GourmetShareMap
//

import SwiftUI

/// プロフィールの記録一覧グリッドの1マス。表紙写真を正方形で敷き詰める。
struct RecordPhotoTile: View {
    let record: ProfileRecord

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(StoreCategoryStyle.color(for: record.category).opacity(0.18))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                // 写真が無い・読み込み中・失敗時は、ジャンルに応じたアイコンにフォールバックする。
                Image(systemName: StoreCategoryStyle.symbolName(for: record.category))
                    .font(.system(size: 22))
                    .foregroundStyle(StoreCategoryStyle.color(for: record.category))
            }
            .overlay {
                if let url = record.coverImageURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color.clear
                        }
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if record.repeatCount > 1 {
                    Text("×\(record.repeatCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 3) {
        RecordPhotoTile(record: ProfileRecord(storeName: "麺屋 はる", category: "ラーメン・麺類", rating: 4, repeatCount: 3))
        RecordPhotoTile(record: ProfileRecord(storeName: "ビストロ", category: "洋食・西洋料理", rating: 4.5, repeatCount: 1))
    }
    .padding()
    .background(Color(red: 0.984, green: 0.968, blue: 0.937))
}
