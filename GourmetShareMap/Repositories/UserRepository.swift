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

    /// ログイン中ユーザーの表示名・自己紹介を更新する。
    /// nil を渡した項目は更新しない（JSON に含めないため既存値が残る）。
    func updateMyProfile(name: String?, bio: String?) async throws {
        struct ProfileUpdate: Encodable {
            let name: String?
            let bio: String?
        }

        let userId = try await client.auth.session.user.id

        try await client
            .from("user")
            .update(ProfileUpdate(name: name, bio: bio))
            .eq("id", value: userId)
            .execute()
    }

    /// user.profile_image にアイコン画像のパスを保存する。
    /// 画像のアップロード自体は ImageRepository（PR-06）で行い、返ってきた profile-images 内のパスを渡す。
    func updateMyProfileImage(path: String) async throws {
        struct ProfileImageUpdate: Encodable {
            let profileImage: String

            enum CodingKeys: String, CodingKey {
                case profileImage = "profile_image"
            }
        }

        let userId = try await client.auth.session.user.id

        try await client
            .from("user")
            .update(ProfileImageUpdate(profileImage: path))
            .eq("id", value: userId)
            .execute()
    }
}
