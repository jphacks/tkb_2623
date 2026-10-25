import Foundation

/// タイムラインに並べる 1 件分（自分またはフレンドの店舗記録）。
nonisolated struct TimelinePost: Equatable, Identifiable, Sendable {
    /// store.id
    let id: UUID
    let storeName: String
    let category: String?
    let memo: String?
    let userID: UUID
    /// user.name。取得できなかったときは nil。
    let userName: String?
    /// user.profile_image の署名付きURL。アイコン未設定・取得失敗時は nil。
    let userAvatarURL: URL?
    let isMine: Bool
    let createdAt: Date
    /// 表紙（最初にアップロードした写真）の署名付きURL。写真がなければ nil。
    let coverImageURL: URL?
}

/// タイムライン画面の表示に必要なデータ一式。
nonisolated struct TimelineFeed: Equatable, Sendable {
    /// created_at 降順。
    let posts: [TimelinePost]
    /// 自分がフォローしているフレンドの人数。
    let friendCount: Int
}
