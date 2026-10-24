import Foundation

/// image列には公開URLではなく、record-images内のオブジェクトパスを保持する。
nonisolated struct ImageRecord: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let storeID: UUID
    let path: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case storeID = "store_id"
        case path = "image"
        case createdAt = "created_at"
    }
}

nonisolated enum RecordImageFormat: String, Sendable {
    case jpeg, png

    var contentType: String { self == .jpeg ? "image/jpeg" : "image/png" }
    var fileExtension: String { self == .jpeg ? "jpg" : "png" }
}

nonisolated enum ImageRepositoryError: LocalizedError {
    case emptyData
    case invalidExpiration
    case storeNotOwned
    case imageNotFound
    case invalidPath
    case cleanupFailed(path: String, insertionError: any Error, cleanupError: any Error)

    var errorDescription: String? {
        switch self {
        case .emptyData: return "画像データが空です。"
        case .invalidExpiration: return "URLの有効期限は1秒以上で指定してください。"
        case .storeNotOwned: return "操作できる自分の店舗記録が見つかりません。"
        case .imageNotFound: return "操作できる画像が見つかりません。"
        case .invalidPath: return "画像の保存先が不正です。"
        case let .cleanupFailed(path, insertionError, cleanupError):
            return "画像行の登録とファイルの後始末に失敗しました（\(path)）: \(insertionError.localizedDescription); \(cleanupError.localizedDescription)"
        }
    }
}
