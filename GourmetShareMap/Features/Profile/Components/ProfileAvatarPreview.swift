//
//  ProfileAvatarPreview.swift
//  GourmetShareMap
//

import SwiftUI
import UIKit

/// プロフィール編集画面のアバタープレビュー。
/// 未保存の選択画像（pendingImageData）があれば優先して表示し、無ければ保存済みのpreviewURLを表示する。
/// どちらも無い、または読み込み・デコードに失敗した場合は固定アイコンにフォールバックする。
struct ProfileAvatarPreview: View {
    let previewURL: URL?
    let pendingImageData: Data?
    var size: CGFloat = 96

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.95, green: 0.80, blue: 0.62), Color(red: 0.89, green: 0.63, blue: 0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: size, height: size)
            .overlay { content }
            .overlay {
                Circle().stroke(Color.white, lineWidth: 3)
            }
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    @ViewBuilder
    private var content: some View {
        if let pendingImageData, let uiImage = UIImage(data: pendingImageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else if let previewURL {
            AsyncImage(url: previewURL) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } else {
                    fallbackIcon
                }
            }
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "person.fill")
            .font(.system(size: size * 0.375))
            .foregroundStyle(.white)
    }
}

#Preview {
    HStack(spacing: 24) {
        ProfileAvatarPreview(previewURL: nil, pendingImageData: nil)
        ProfileAvatarPreview(previewURL: URL(string: "https://example.com/avatar.jpg"), pendingImageData: nil)
    }
    .padding()
    .background(Color(red: 0.984, green: 0.968, blue: 0.937))
}
