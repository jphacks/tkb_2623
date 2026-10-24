//
//  CardBackground.swift
//  GourmetShareMap
//

import SwiftUI

extension View {
    /// 白背景＋枠線のカード表示。
    func cardBackground(cornerRadius: CGFloat = 14) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(.appCard, in: shape)
            .overlay(shape.strokeBorder(.appBorder, lineWidth: 1))
    }
}
