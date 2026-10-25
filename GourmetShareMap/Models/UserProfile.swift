import Foundation

/// ログイン中ユーザー自身のプロフィール。既存DBの `user` に対応する。
/// user テーブルのRLS（auth.uid() = id の行のみ参照可）により、常に自分の行だけが返る。
nonisolated struct UserProfile: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// フレンド検索に使うユーザー名。DBでは NOT NULL（登録時に自動採番）だが、
    /// migration 適用前のDBでも読み込めるよう Optional にしている。
    let userName: String?
    let name: String?
    let bio: String?
    let profileImage: String?

    init(id: UUID, userName: String? = nil, name: String?, bio: String?, profileImage: String?) {
        self.id = id
        self.userName = userName
        self.name = name
        self.bio = bio
        self.profileImage = profileImage
    }

    enum CodingKeys: String, CodingKey {
        case id, name, bio
        case userName = "user_name"
        case profileImage = "profile_image"
    }
}
