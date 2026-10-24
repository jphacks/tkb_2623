//
//  RecommendationSheet.swift
//  GourmetShareMap
//

import SwiftUI

/// レコメンド結果。まんぷく先生が薦めた1件を、予測評価と理由つきで出す。
// TODO: レコメンド結果画面の仕様が決まったら差し替える（候補を複数出す／マップにピンを立てる等）。
struct RecommendationSheet: View {
    let recommendation: Recommendation
    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            MascotAnimationView(level: .lv3, framesPerSecond: 6)
                .frame(height: 120)
                .padding(.top, 24)

            VStack(spacing: 14) {
                Text("ここ、好きだと思います")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.appPrimary)

                Text(recommendation.name)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(.appText)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    CategoryBadge(category: recommendation.category)

                    HStack(spacing: 5) {
                        StarRatingView(rating: recommendation.predictedRating)
                        Text(String(format: "%.1f", recommendation.predictedRating))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.appText)
                            .monospacedDigit()
                    }
                }

                Text(recommendation.reason)
                    .font(.system(size: 13))
                    .foregroundStyle(.appText.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                Text("★は、あなたの記録から予測した評価です")
                    .font(.system(size: 11))
                    .foregroundStyle(.appText.opacity(0.4))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer(minLength: 16)

            Button(action: onClose) {
                Text("閉じる")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(.appPrimary, in: Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.appBackground)
        .presentationDetents([.medium])
    }
}

#Preview {
    RecommendationSheet(
        recommendation: Recommendation(
            placeID: "preview",
            name: "中華そば 一会",
            category: "ラーメン",
            predictedRating: 4.3,
            reason: "ラーメンの記録が8件あって、平均★4.3。似た雰囲気のお店です。"
        )
    )
}
