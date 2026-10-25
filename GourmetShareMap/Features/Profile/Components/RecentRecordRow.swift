//
//  RecentRecordRow.swift
//  GourmetShareMap

import SwiftUI

struct RecentRecordRow: View {
    let record: ProfileRecord

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                Text(record.storeName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)

                HStack(spacing: 8) {
                    CategoryBadge(category: record.category)
                    StarRatingView(rating: record.rating)
                    Text("リピート\(record.repeatCount)回")
                        .font(.system(size: 12))
                        .foregroundStyle(.black.opacity(0.5))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
    }

    /// 表紙写真。写真が無い・読み込み中・失敗時は固定アイコンを表示する。
    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(red: 0.93, green: 0.86, blue: 0.72))
            .frame(width: 64, height: 64)
            .overlay {
                Image(systemName: "fork.knife")
                    .foregroundStyle(.white)
                    .font(.system(size: 20))
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
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    RecentRecordRow(record: ProfileRecord(storeName: "麺屋 はる", category: "ラーメン", rating: 4, repeatCount: 3))
        .padding()
        .background(Color(red: 0.984, green: 0.968, blue: 0.937))
}
