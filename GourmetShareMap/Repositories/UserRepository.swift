//
//  UserRepository.swift
//  GourmetShareMap
//

import Foundation
import Supabase

// TODO: PR-04（API実装）で user の取得・更新メソッドが追加されたら、このファイルに統合する。
final class UserRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseManager.shared.client) {
        self.client = client
    }

    /// ログイン中ユーザー自身の記録（store）件数を返す。
    /// head: true で行データは取得せず、件数だけを取得する。
    func fetchMyRecordCount() async throws -> Int {
        let userId = try await client.auth.session.user.id

        // store の RLS はフォロー中フレンドの行も返すため、user_id で自分の行に絞る。
        let response = try await client
            .from("store")
            .select("*", head: true, count: .exact)
            .eq("user_id", value: userId)
            .execute()

        return response.count ?? 0
    }
}
