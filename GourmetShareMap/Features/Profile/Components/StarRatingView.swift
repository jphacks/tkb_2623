//
//  StarRatingView.swift
//  GourmetShareMap
//

import SwiftUI

/// 0〜5の評価値を★アイコン5つで表示する。
struct StarRatingView: View {
    let rating: Double
    var starColor: Color = Color(red: 0.76, green: 0.35, blue: 0.22)

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: symbolName(for: index))
                    .foregroundStyle(starColor)
                    .font(.system(size: 13))
            }
        }
    }

    private func symbolName(for index: Int) -> String {
        let fillAmount = rating - Double(index)
        if fillAmount >= 1 {
            return "star.fill"
        } else if fillAmount >= 0.5 {
            return "star.leadinghalf.filled"
        } else {
            return "star"
        }
    }
}

#Preview {
    StarRatingView(rating: 4)
        .padding()
}
