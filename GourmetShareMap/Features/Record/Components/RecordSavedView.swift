//
//  RecordSavedView.swift
//  GourmetShareMap
//

import SwiftUI

/// 保存完了時に画面中央に出すカード。保存した内容を見せて、完了がひと目でわかるようにする。
struct RecordSavedView: View {
    let summary: RecordCreateViewModel.SavedSummary
    let onClose: () -> Void

    @State private var isCheckmarkVisible = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.appPrimary)
                    .symbolEffect(.bounce, value: isCheckmarkVisible)
                    .scaleEffect(isCheckmarkVisible ? 1 : 0.4)
                    .opacity(isCheckmarkVisible ? 1 : 0)
                    // アニメーションはチェックマークだけに限定する（カード全体が動かないように）。
                    .animation(.spring(duration: 0.45, bounce: 0.4), value: isCheckmarkVisible)

                Text("記録を保存しました")
                    .font(.title3.bold())

                storeSummary

                Button(action: onClose) {
                    Text("続けて登録する")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(.appPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .foregroundStyle(.appText)
            .padding(24)
            .background(.appBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 32)
        }
        .onAppear {
            isCheckmarkVisible = true
        }
        .accessibilityAddTraits(.isModal)
    }

    private var storeSummary: some View {
        HStack(spacing: 12) {
            if let cover = summary.coverImage {
                Image(uiImage: cover)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.storeName)
                    .font(.headline)
                    .lineLimit(2)
                if let category = summary.category {
                    Text(category)
                        .font(.caption)
                        .foregroundStyle(.appText.opacity(0.6))
                }
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { value in
                        Image(systemName: value <= summary.rating ? "star.fill" : "star")
                            .font(.caption)
                            .foregroundStyle(value <= summary.rating ? AnyShapeStyle(.appPrimary) : AnyShapeStyle(.appBorder))
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("評価 星\(summary.rating)")
                Text("\(summary.repeatNum)回目の訪問・写真\(summary.photoCount)枚")
                    .font(.caption)
                    .foregroundStyle(.appText.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .cardBackground()
    }
}

#Preview {
    RecordSavedView(
        summary: .init(storeName: "麺屋 はる", category: "ラーメン・麺類", rating: 4, repeatNum: 2, photoCount: 3, coverImage: nil),
        onClose: {}
    )
}
