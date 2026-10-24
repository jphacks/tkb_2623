//
//  StorePhotoThumbnail.swift
//  GourmetShareMap

import SwiftUI

/// 店舗の1枚目の写真。写真が無い店舗・取得に失敗した場合はカテゴリ色のプレースホルダーを出す。
/// 画像はStorageの署名付きURL経由で取得するため、選択された店舗の分だけ遅延読み込みする。
struct StorePhotoThumbnail: View {
    let storeID: UUID
    let category: String
    var size: CGFloat = 64

    @State private var imageURL: URL?

    private let repository = ImageRepository()

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(StoreCategoryStyle.color(for: category).opacity(0.55))
            .frame(width: size, height: size)
            .overlay {
                if let imageURL {
                    AsyncImage(url: imageURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView().tint(.white)
                    }
                } else {
                    Image(systemName: StoreCategoryStyle.symbolName(for: category))
                        .foregroundStyle(.white)
                        .font(.system(size: 22))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            // 選択店舗が変わるたびに読み込み直し、前の店舗の写真が残らないようにする。
            .task(id: storeID) {
                imageURL = await loadFirstImageURL()
            }
    }

    private func loadFirstImageURL() async -> URL? {
        do {
            guard let first = try await repository.fetchImages(storeID: storeID).first else {
                return nil
            }
            return try await repository.signedURL(imageID: first.id)
        } catch {
            // 写真はおまけの情報なので、失敗してもプレースホルダー表示に留める。
            return nil
        }
    }
}

#Preview {
    StorePhotoThumbnail(storeID: UUID(), category: "ラーメン・麺類")
        .padding()
}
