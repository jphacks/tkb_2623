//
//  StorePhotoLoader.swift
//  GourmetShareMap
//

import Observation
import UIKit

/// 店舗の1枚目の写真を、地図のピンに載せられる小さなビットマップとして供給する。
///
/// ピン1つあたり「image行の取得 → 署名付きURLの発行 → ダウンロード」と往復が多いため、
/// 一度読んだ店舗は結果を保持し、写真が無い店舗も再取得しないよう記録する。
@MainActor
@Observable
final class StorePhotoLoader {
    private(set) var photos: [UUID: UIImage] = [:]

    /// 写真が無い、または取得に失敗した店舗。何度も往復しないために覚えておく。
    private var skipped: Set<UUID> = []
    private var inFlight: Set<UUID> = []

    private let repository: ImageRepository
    /// ピンの表示サイズ(56pt)に対して、3倍解像度まで見込んだ一辺。
    private let maxPixelSize: CGFloat = 168

    init(repository: ImageRepository? = nil) {
        self.repository = repository ?? ImageRepository()
    }

    func photo(for storeID: UUID) -> UIImage? {
        photos[storeID]
    }

    /// まだ読んでいない店舗の写真をまとめて取得する。
    /// 1件の失敗が他をキャンセルしないよう、エラーはその店舗だけで握りつぶす。
    func load(storeIDs: [UUID]) async {
        let targets = storeIDs.filter { id in
            photos[id] == nil && !skipped.contains(id) && !inFlight.contains(id)
        }
        guard !targets.isEmpty else { return }
        inFlight.formUnion(targets)

        await withTaskGroup(of: (UUID, UIImage?).self) { group in
            for storeID in targets {
                group.addTask { @MainActor [self] in
                    (storeID, await loadPhoto(storeID: storeID))
                }
            }
            for await (storeID, image) in group {
                inFlight.remove(storeID)
                if let image {
                    photos[storeID] = image
                } else {
                    skipped.insert(storeID)
                }
            }
        }
    }

    private func loadPhoto(storeID: UUID) async -> UIImage? {
        do {
            guard let first = try await repository.fetchImages(storeID: storeID).first else {
                return nil
            }
            let url = try await repository.signedURL(imageID: first.id)
            let (data, _) = try await URLSession.shared.data(from: url)
            return Self.downsampled(data: data, maxPixelSize: maxPixelSize)
        } catch {
            // 写真は補助的な情報なので、失敗してもカテゴリアイコンのピンにフォールバックする。
            return nil
        }
    }

    /// 原寸のまま展開するとピン1つで数MBになるため、ピンの表示サイズまで縮めてから渡す。
    private static func downsampled(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: thumbnail)
    }
}
