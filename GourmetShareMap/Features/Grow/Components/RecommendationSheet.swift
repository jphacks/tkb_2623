//
//  RecommendationSheet.swift
//  GourmetShareMap
//

import SwiftUI

/// レコメンド結果。相棒が薦めた上位3件を、予測評価と理由つきで出す。
/// 下にスワイプすれば閉じられる標準のシート動作に任せるため、専用の閉じるボタンは置かない。
struct RecommendationSheet: View {
    let recommendations: [Recommendation]

    /// 一番のおすすめ（先頭の1件）のカテゴリで、一番育ったキャラ（Lv.3）を出す。
    private var character: MascotCharacter {
        MascotCharacterMapping.character(for: recommendations.first?.category ?? "その他", level: .lv3)
    }

    var body: some View {
        VStack(spacing: 0) {
            MascotAnimationView(character: character, level: .lv3, framesPerSecond: 6)
                .frame(height: 100)
                .padding(.top, 20)

            Text("ここ、好きだと思います")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.appPrimary)
                .padding(.top, 6)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(recommendations) { recommendation in
                        card(for: recommendation)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.appBackground)
        .presentationDetents([.medium, .large])
    }

    private func card(for recommendation: Recommendation) -> some View {
        VStack(spacing: 8) {
            Text(recommendation.name)
                .font(.system(size: 18, weight: .heavy))
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
                .font(.system(size: 12.5))
                .foregroundStyle(.appText.opacity(0.65))
                .multilineTextAlignment(.center)

            if let mapsURL = recommendation.mapsURL {
                Link(destination: mapsURL) {
                    HStack(spacing: 4) {
                        Image(systemName: "map")
                            .font(.system(size: 12, weight: .bold))
                        Text("Google Mapsで見る")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.appPrimary)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.appCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.appBorder, lineWidth: 1)
        }
    }
}

#Preview {
    RecommendationSheet(
        recommendations: [
            Recommendation(
                placeID: "preview-1",
                name: "中華そば 一会",
                category: "ラーメン・麺類",
                predictedRating: 4.3,
                reason: "「ラーメン食べたい」に近い、ラーメン・麺類の記録が8件あって平均★4.3。"
            ),
            Recommendation(
                placeID: "preview-2",
                name: "麺屋 風花",
                category: "ラーメン・麺類",
                predictedRating: 4.1,
                reason: "「ラーメン食べたい」に近い、ラーメン・麺類の記録が8件あって平均★4.3。"
            ),
        ]
    )
}
