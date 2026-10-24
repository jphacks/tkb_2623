//
//  MapLegendView.swift
//  GourmetShareMap

import SwiftUI

/// ピンの枠色が「自分」「フレンド」のどちらを表すかを示す凡例。
struct MapLegendView: View {
    private let accentOrange = Color(red: 0.76, green: 0.35, blue: 0.22)

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            legendRow(symbol: "circle", label: "白枠:自分", color: Color.black.opacity(0.4))
            legendRow(symbol: "circle.fill", label: "色枠:フレンド", color: accentOrange)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.black.opacity(0.55))
    }

    private func legendRow(symbol: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(label)
        }
    }
}

#Preview {
    MapLegendView()
        .padding()
}
