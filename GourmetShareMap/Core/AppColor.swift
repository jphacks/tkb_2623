//
//  AppColor.swift
//  GourmetShareMap
//

import SwiftUI

// アプリ共通のカラーパレット。
// `ShapeStyle where Self == Color` に定義しているので `.foregroundStyle(.appText)` と `Color.appText` の両方で使える。
extension ShapeStyle where Self == Color {
    static var appBackground: Color { Color(hex: 0xFFF9F2) }
    static var appCard: Color { Color(hex: 0xFFFFFF) }
    static var appText: Color { Color(hex: 0x2D2926) }
    static var appPrimary: Color { Color(hex: 0xD65A31) }
    static var appBorder: Color { Color(hex: 0xE8DEDE) }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
