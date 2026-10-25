import Foundation

/// 自分がブロックしているユーザー1件（プロフィール画面の一覧表示用）。
nonisolated struct BlockedUser: Equatable, Identifiable, Sendable {
    /// user.id（blocked_user.blocked_id）。
    let id: UUID
    /// user.name。取得できなかったときは nil。
    let name: String?
    /// ブロックした日時。
    let createdAt: Date
}
