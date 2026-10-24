import Foundation

/// ログイン中ユーザー自身のプロフィール。既存DBの `user` に対応する。
/// user テーブルのRLS（auth.uid() = id の行のみ参照可）により、常に自分の行だけが返る。
nonisolated struct UserProfile: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String?
    let bio: String?
    let profileImage: String?

    enum CodingKeys: String, CodingKey {
        case id, name, bio
        case profileImage = "profile_image"
    }
}
