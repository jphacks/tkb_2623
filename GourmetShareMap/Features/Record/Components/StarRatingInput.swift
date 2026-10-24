//
//  StarRatingInput.swift
//  GourmetShareMap
//

import SwiftUI

/// 1〜5 の星評価。0 は未評価。
struct StarRatingInput: View {
    @Binding var rating: Int
    var maxRating = 5

    var body: some View {
        HStack(spacing: 10) {
            ForEach(1...maxRating, id: \.self) { value in
                Button {
                    withAnimation(.snappy) { rating = value }
                } label: {
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .font(.system(size: 30))
                        .foregroundStyle(value <= rating ? AnyShapeStyle(.appPrimary) : AnyShapeStyle(.appBorder))
                        .symbolEffect(.bounce, value: rating == value)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("評価")
        .accessibilityValue(rating == 0 ? "未評価" : "星\(rating)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(rating + 1, maxRating)
            case .decrement: rating = max(rating - 1, 0)
            @unknown default: break
            }
        }
    }
}

#Preview {
    @Previewable @State var rating = 3
    StarRatingInput(rating: $rating)
}
