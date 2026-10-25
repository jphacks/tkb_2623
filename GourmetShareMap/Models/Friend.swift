import Foundation

/// フレンド一覧・検索結果・受け取った申請に表示する相手のプロフィール。既存DBの `user` の一部の列に対応する。
nonisolated struct FriendUser: Decodable, Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    let userName: String
    let name: String?
    /// profile-images バケット内のオブジェクトパス。
    let profileImage: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case userName = "user_name"
        case profileImage = "profile_image"
    }

    /// 表示名。未設定なら user_name を出す。
    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return name }
        return userName
    }
}

/// ログイン中ユーザーから見た、検索した相手との関係。DB関数 search_user_by_user_name の relation 列に対応する。
nonisolated enum FriendRelation: String, Decodable, Sendable {
    /// 自分自身
    case me = "self"
    /// 既にフレンド
    case friend
    /// 自分が申請済み（承認待ち）
    case requested
    /// 相手から申請が来ている
    case incoming
    /// 上記以外（申請できる）
    case none
}

/// user_name の完全一致検索の結果。
nonisolated struct FriendSearchResult: Equatable, Sendable {
    let user: FriendUser
    let relation: FriendRelation
}

/// 自分宛てに届いている承認待ちのフレンド申請。
nonisolated struct FriendRequest: Equatable, Identifiable, Sendable {
    let requester: FriendUser
    let createdAt: Date

    var id: UUID { requester.id }
}

/// フレンド申請を送った結果。DB関数 send_friend_request の戻り値に対応する。
nonisolated enum FriendRequestSendResult: String, Decodable, Sendable {
    /// 申請した（相手の承認待ち）
    case requested
    /// 相手から申請が来ていたため、その場で承認してフレンドになった
    case accepted
}
