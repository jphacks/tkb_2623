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
    let isMine: Bool
    let createdAt: Date
    /// 表紙（最初にアップロードした写真）の署名付きURL。写真がなければ nil。
    let coverImageURL: URL?
    /// この記録に付いたコメントの件数。
    let commentCount: Int
    /// この記録に付いたいいねの件数。
    let likeCount: Int
    /// 自分がいいね済みかどうか。
    let isLikedByMe: Bool

    /// いいねボタンの楽観的更新用。状態を反転し、件数を合わせて増減した複製を返す。
    func togglingLike() -> TimelinePost {
        TimelinePost(
            id: id, storeName: storeName, category: category, memo: memo, userID: userID,
            userName: userName, isMine: isMine, createdAt: createdAt, coverImageURL: coverImageURL,
            commentCount: commentCount,
            likeCount: isLikedByMe ? max(0, likeCount - 1) : likeCount + 1,
            isLikedByMe: !isLikedByMe
        )
    }
}

/// タイムライン画面の表示に必要なデータ一式。
nonisolated struct TimelineFeed: Equatable, Sendable {
    /// created_at 降順。
    let posts: [TimelinePost]
    /// 自分がフォローしているフレンドの人数。
    let friendCount: Int
}
