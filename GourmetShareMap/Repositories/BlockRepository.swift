import Foundation
import Supabase

/// block_user() RPC に渡すパラメータ。
private nonisolated struct BlockUserParams: Encodable {
    let targetId: UUID

    enum CodingKeys: String, CodingKey {
        case targetId = "target_id"
    }
}

private nonisolated struct BlockedUserRow: Decodable {
    let blockedId: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case blockedId = "blocked_id"
        case createdAt = "created_at"
    }
}

private nonisolated struct BlockedUserNameRow: Decodable {
    let id: UUID
    let name: String?
}

@MainActor
final class BlockRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) { self.client = client }
    convenience init() { self.init(client: SupabaseManager.shared.client) }

    /// 指定したユーザーをブロックする。
    /// DB側のblock_user() RPCが、ブロックの登録と既存フォロー関係の双方向解除を
    /// アトミックに行う（自分の行しか削除できないRLSでは相手側の行を消せないため）。
    func block(userID: UUID) async throws {
        _ = try await client.auth.session
        try await client.rpc("block_user", params: BlockUserParams(targetId: userID)).execute()
    }

    /// ブロックを解除する。blocked_userの「自分の行」削除はRLSで許可されているため、
    /// block()と違ってRPCは不要。
    func unblock(userID: UUID) async throws {
        let myID = try await client.auth.session.user.id
        try await client
            .from("blocked_user")
            .delete()
            .eq("blocker_id", value: myID)
            .eq("blocked_id", value: userID)
            .execute()
    }

    /// 自分がブロックしているユーザーを、ブロックした日時の新しい順で返す。
    func fetchBlockedUsers() async throws -> [BlockedUser] {
        let myID = try await client.auth.session.user.id

        let rows: [BlockedUserRow] = try await client
            .from("blocked_user")
            .select("blocked_id, created_at")
            .eq("blocker_id", value: myID)
            .order("created_at", ascending: false)
            .execute().value
        guard !rows.isEmpty else { return [] }

        let names = try await fetchUserNames(Set(rows.map(\.blockedId)))
        return rows.map { row in
            BlockedUser(id: row.blockedId, name: names[row.blockedId], createdAt: row.createdAt)
        }
    }

    private func fetchUserNames(_ ids: Set<UUID>) async throws -> [UUID: String] {
        guard !ids.isEmpty else { return [:] }
        let users: [BlockedUserNameRow] = try await client.from("user")
            .select("id, name")
            .in("id", values: ids.map(\.uuidString))
            .execute().value
        return users.reduce(into: [:]) { result, user in
            if let name = user.name, !name.isEmpty { result[user.id] = name }
        }
    }
}
