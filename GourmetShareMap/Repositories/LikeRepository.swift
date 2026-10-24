import Foundation
import Supabase

@MainActor
final class LikeRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) { self.client = client }
    convenience init() { self.init(client: SupabaseManager.shared.client) }

    /// 二重タップで2回送っても、重複登録にはならない（ignoreDuplicates）。
    /// 閲覧できる記録（本人 or フレンドの記録）にだけいいねできる。範囲外はDBのINSERT RLSで拒否される。
    func like(storeID: UUID) async throws {
        let userID = try await client.auth.session.user.id
        try await client.from("store_like")
            .upsert(
                StoreLikeInsert(storeID: storeID, userID: userID),
                onConflict: "store_id,user_id",
                ignoreDuplicates: true
            )
            .execute()
    }

    /// 本人のいいねのみ取り消せる。対象外はDBのDELETE RLSで拒否され0件になる。
    func unlike(storeID: UUID) async throws {
        let userID = try await client.auth.session.user.id
        try await client.from("store_like")
            .delete()
            .eq("store_id", value: storeID.uuidString)
            .eq("user_id", value: userID.uuidString)
            .execute()
    }
}

private nonisolated struct StoreLikeInsert: Encodable {
    let storeID: UUID
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case storeID = "store_id"
        case userID = "user_id"
    }
}
