//
//  UserRepository.swift
//  GourmetShareMap
//

import Foundation
import Supabase

nonisolated enum UserRepositoryError: LocalizedError {
    case emptyData
    case invalidExpiration
    case cleanupFailed(path: String, updateError: any Error, cleanupError: any Error)

    var errorDescription: String? {
        switch self {
        case .emptyData: return "画像データが空です。"
        case .invalidExpiration: return "URLの有効期限は1秒以上で指定してください。"
        case let .cleanupFailed(path, updateError, cleanupError):
            return "プロフィール画像の保存とファイルの後始末に失敗しました（\(path)）: \(updateError.localizedDescription); \(cleanupError.localizedDescription)"
        }
    }
}

// TODO: PR-04（API実装）で user の取得・更新メソッドが追加されたら、このファイルに統合する。
final class UserRepository {
    private let client: SupabaseClient
    private let profileImagesBucket = "profile-images"

    init(client: SupabaseClient = SupabaseManager.shared.client) {
        self.client = client
    }

    /// ログイン中ユーザー自身のプロフィール（表示名・自己紹介・アイコン画像パス）を取得する。
    /// user テーブルのRLS（auth.uid() = id の行のみ参照可）により、他ユーザーの行は取得できない。
    func fetchMyProfile() async throws -> UserProfile {
        let userId = try await client.auth.session.user.id

        return try await client
            .from("user")
            .select("id, name, bio, profile_image")
            .eq("id", value: userId)
            .single()
            .execute()
            .value
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

    /// プロフィール画像をprofile-imagesバケットへアップロードし、user.profile_imageを新しいパスへ更新する。
    /// 更新に成功した後、置き換え前の画像がStorageに残っていれば削除する（旧画像は残さない）。
    /// パスは必ず `<user_id>/<filename>` 形式（Storage側RLSの要件）。
    @discardableResult
    func uploadProfileImage(data: Data, format: RecordImageFormat = .jpeg) async throws -> String {
        guard !data.isEmpty else { throw UserRepositoryError.emptyData }
        let userID = try await client.auth.session.user.id
        let oldPath = try await fetchMyProfile().profileImage

        let newPath = "\(userID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(format.fileExtension)"
        try await client.storage.from(profileImagesBucket).upload(
            newPath, data: data, options: FileOptions(contentType: format.contentType, upsert: false)
        )

        do {
            try await updateMyProfileImage(path: newPath)
        } catch {
            let updateError = error
            do { try await client.storage.from(profileImagesBucket).remove(paths: [newPath]) }
            catch {
                throw UserRepositoryError.cleanupFailed(path: newPath, updateError: updateError, cleanupError: error)
            }
            throw updateError
        }

        if let oldPath, oldPath != newPath {
            do { try await client.storage.from(profileImagesBucket).remove(paths: [oldPath]) }
            catch let error as StorageError where error.statusCode == "404" {
                // 既に削除済みなら無視する。
            }
        }

        return newPath
    }

    /// 保存済みのprofile_imageパスから、表示用の署名付きURLを取得する。
    /// 本人・フレンドの閲覧権限はStorageのRLSに委ねる。
    func signedURL(path: String, expiresIn: Int = 3600) async throws -> URL {
        guard expiresIn > 0 else { throw UserRepositoryError.invalidExpiration }
        _ = try await client.auth.session
        return try await client.storage.from(profileImagesBucket).createSignedURL(path: path, expiresIn: expiresIn)
    }
}
