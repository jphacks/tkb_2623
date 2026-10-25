//
//  ShopPinView.swift
//  GourmetShareMap

import SwiftUI

/// 地図上の店舗ピン。`GMSMarker.icon` に渡すため `ImageRenderer` でビットマップ化される。
/// そのためモデルではなく描画に必要な値だけを受け取り、キャッシュのキーにしやすくしている。
struct ShopPinView: View {
    let category: String
    let isMine: Bool
    /// 自分とフレンドの両方が登録している店舗。フレンドアイコンを重ねる。
    let sharedWithFriend: Bool
    let isSelected: Bool
    /// 店舗の1枚目の写真。未登録・取得失敗時はnilで、カテゴリアイコンにフォールバックする。
    var photo: UIImage?

    private let size: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                thumbnail
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(borderColor, lineWidth: 3)
                    }

                if sharedWithFriend {
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
        // ビットマップ化するため、影やアイコンのはみ出しが切れないよう余白を確保する。
        .padding(6)
        .scaleEffect(isSelected ? 1.12 : 1.0)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
        } else {
            categoryColor.opacity(0.55)
                .overlay {
                    Image(systemName: StoreCategoryStyle.symbolName(for: category))
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                }
        }
    }

    private var categoryColor: Color {
        StoreCategoryStyle.color(for: category)
    }

    private var borderColor: Color {
        isMine ? Color.white : categoryColor
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
        ShopPinView(category: "ラーメン・麺類", isMine: true, sharedWithFriend: true, isSelected: true)
        ShopPinView(category: "洋食・西洋料理", isMine: false, sharedWithFriend: false, isSelected: false)
        ShopPinView(category: "カフェ・喫茶", isMine: true, sharedWithFriend: false, isSelected: false)
    }
    .padding()
    .background(Color(red: 0.90, green: 0.93, blue: 0.87))
}
