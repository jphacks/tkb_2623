import Foundation

/// タイムラインの記録（store）に付いたコメント 1 件分。
/// `Testing`フレームワークの`Comment`（テストの注釈用の型）と名前が衝突するため、
/// 単純な`Comment`ではなく`TimelineComment`にしている。
nonisolated struct TimelineComment: Equatable, Identifiable, Sendable {
    let id: UUID
    let storeID: UUID
    let userID: UUID
    /// user.name。取得できなかったときは nil。
    let userName: String?
    /// user.profile_image の署名付きURL。未設定・取得できなかったときは nil。
    let avatarURL: URL?
    let body: String
    let isMine: Bool
    let createdAt: Date
}

/// `comment`テーブルの行。Repository内のデコード・エンコードに使う。
nonisolated struct CommentRecord: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let storeID: UUID
    let userID: UUID
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body
        case storeID = "store_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }
}
