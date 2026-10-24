//
//  MapLegendView.swift
//  GourmetShareMap

import SwiftUI

/// ピンの枠色が「自分」「フレンド」のどちらを表すかを示す凡例。
///
/// 絞り込みの行に並べると、左寄せのコントロールに対してこの小さな文字だけが
/// 右マージンに貼り付いて見え、狭い端末や文字サイズ拡大時には収まらなくなる。
/// 説明対象である地図の上に小さく重ねる。
struct MapLegendView: View {
    private let accentOrange = Color(red: 0.76, green: 0.35, blue: 0.22)

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            legendRow(symbol: "circle", label: "白枠:自分", color: Color.black.opacity(0.4))
            legendRow(symbol: "circle.fill", label: "色枠:フレンド", color: accentOrange)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.black.opacity(0.65))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // 地図の上でも読めるようにする。不透明の板で覆うより地図が見える。
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func legendRow(symbol: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(label)
                .fixedSize()
        }
    }
}

#Preview {
    MapLegendView()
        .padding()
        .background(Color(red: 0.90, green: 0.93, blue: 0.87))
}
