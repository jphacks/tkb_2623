//
//  ShopPinView.swift
//  GourmetShareMap

import SwiftUI

struct ShopPinView: View {
    let shop: MapShop
    let isSelected: Bool

    private let size: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(categoryColor.opacity(0.55))
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(borderColor, lineWidth: 3)
                    }

                if shop.sharedWithFriend {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(categoryColor)
                        }
                        .offset(x: 8, y: -8)
                }
            }
            .shadow(color: Color.black.opacity(0.18), radius: 4, y: 2)

            PinTailShape()
                .fill(categoryColor)
                .frame(width: 14, height: 9)
        }
        .scaleEffect(isSelected ? 1.12 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }

    private var categoryColor: Color {
        switch shop.category {
        case "ラーメン": Color(red: 0.86, green: 0.42, blue: 0.24)
        case "洋食": Color(red: 0.33, green: 0.52, blue: 0.80)
        case "和食": Color(red: 0.45, green: 0.62, blue: 0.42)
        case "中華": Color(red: 0.80, green: 0.60, blue: 0.20)
        case "カフェ": Color(red: 0.56, green: 0.43, blue: 0.31)
        default: Color.gray
        }
    }

    private var borderColor: Color {
        shop.owner == .me ? Color.white : categoryColor
    }
}

private struct PinTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    HStack(spacing: 24) {
        ShopPinView(shop: MapMockData.shops[0], isSelected: true)
        ShopPinView(shop: MapMockData.shops[3], isSelected: false)
    }
    .padding()
    .background(Color(red: 0.90, green: 0.93, blue: 0.87))
}
