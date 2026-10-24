//
//  GrowStatTile.swift
//  GourmetShareMap
//

import SwiftUI

/// 学習データ数・モデルの性能を並べる小さなカード。
struct GrowStatTile: View {
    let title: String
    let value: String
    var unit: String?
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.appText.opacity(0.55))

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 23, weight: .heavy))
                    .foregroundStyle(.appText)
                    .monospacedDigit()

                if let unit {
                    Text(unit)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.appText.opacity(0.6))
                }
            }

            Text(note ?? " ")
                .font(.system(size: 10.5))
                .foregroundStyle(.appText.opacity(0.45))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .cardBackground(cornerRadius: 16)
    }
}

#Preview {
    HStack(spacing: 10) {
        GrowStatTile(title: "教えたお店", value: "12", unit: "件", note: "AIの学習データ")
        GrowStatTile(title: "好みの読み当て", value: "79", unit: "%", note: "5段階で±0.8のズレ")
    }
    .padding()
    .background(.appBackground)
}
