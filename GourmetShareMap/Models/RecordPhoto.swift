//
//  RecordPhoto.swift
//  GourmetShareMap
//

import CoreLocation
import ImageIO
import PhotosUI
import SwiftUI
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

    /// 画像ファイルのデータから作る。EXIF の位置・日時もここで読み取る。
    /// アプリ内カメラで撮った写真には位置情報が入らないため、location は nil（現在地にフォールバック）。
    @concurrent
    static func make(from data: Data) async -> RecordPhoto? {
        guard let image = downsample(data) else { return nil }
        return RecordPhoto(
            image: image,
            location: PhotoLocationReader.location(from: data),
            takenAt: PhotoLocationReader.takenAt(from: data)
        )
    }

    /// ライブラリで選ばれた写真をまとめて読み込む。読み込めなかった写真は除く。
    static func load(from items: [PhotosPickerItem]) async -> [RecordPhoto] {
        var photos: [RecordPhoto] = []
        for item in items {
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                let photo = await make(from: data)
            else { continue }
            photos.append(photo)
        }
        return photos
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
