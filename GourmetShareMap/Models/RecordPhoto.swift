//
//  RecordPhoto.swift
//  GourmetShareMap
//

import CoreLocation
import ImageIO
import UIKit

/// 登録画面で選択中の写真 1 枚分。並び順の先頭が表紙。
nonisolated struct RecordPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    /// EXIF の撮影位置。カメラで撮った写真やライブラリで位置情報がない写真では nil。
    let location: CLLocationCoordinate2D?
    let takenAt: Date?
}

extension RecordPhoto {
    /// 表示・アップロード用に長辺をこのサイズまで縮小して保持する（フル解像度のままだとメモリを圧迫するため）。
    nonisolated static let maxPixelSize = 2048

    /// ライブラリから読み込んだ画像データから作る。EXIF の位置・日時もここで読み取る。
    @concurrent
    static func make(from data: Data) async -> RecordPhoto? {
        guard let image = downsample(data) else { return nil }
        return RecordPhoto(
            image: image,
            location: PhotoLocationReader.location(from: data),
            takenAt: PhotoLocationReader.takenAt(from: data)
        )
    }

    /// カメラで撮影した画像から作る。位置は持たないので現在地にフォールバックさせる。
    static func make(fromCapturedImage image: UIImage) async -> RecordPhoto {
        let scale = CGFloat(maxPixelSize) / max(image.size.width, image.size.height)
        let resized = scale < 1
            ? await image.byPreparingThumbnail(ofSize: CGSize(width: image.size.width * scale, height: image.size.height * scale))
            : nil
        return RecordPhoto(image: resized ?? image, location: nil, takenAt: .now)
    }

    /// アップロード用の JPEG データ。エンコードはメインスレッドの外で行う。
    @concurrent
    func jpegData() async -> Data? {
        image.jpegData(compressionQuality: 0.8)
    }

    nonisolated private static func downsample(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
