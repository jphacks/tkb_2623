import Foundation
import Supabase

nonisolated enum CommentRepositoryError: LocalizedError {
    case emptyBody
    case bodyTooLong
    case notFound

    var errorDescription: String? {
        switch self {
        case .emptyBody: return "コメントを入力してください。"
        case .bodyTooLong: return "コメントは500文字以内で入力してください。"
        case .notFound: return "操作できるコメントが見つかりません。"
        }
    }
}

@MainActor
final class CommentRepository {
    private let client: SupabaseClient
    private let profileImagesBucket = "profile-images"
    private let signedURLExpiresIn = 3600

    init(client: SupabaseClient) { self.client = client }
    convenience init() { self.init(client: SupabaseManager.shared.client) }

    /// 指定した記録のコメント一覧。古い順（会話として読める順）。
    /// 本人・フレンドの記録だけが返ることは`comment`のSELECT RLSポリシーが保証する。
    func fetchComments(storeID: UUID) async throws -> [TimelineComment] {
        let userID = try await client.auth.session.user.id
        let records: [CommentRecord] = try await client.from("comment")
            .select()
            .eq("store_id", value: storeID.uuidString)
            .order("created_at", ascending: true)
            .order("id", ascending: true)
            .execute().value
        let authors = try await fetchAuthors(Set(records.map(\.userID)))
        return records.map { record in
            let author = authors[record.userID]
            return TimelineComment(
                id: record.id, storeID: record.storeID, userID: record.userID,
                userName: author?.name, avatarURL: author?.avatarURL, body: record.body,
                isMine: record.userID == userID, createdAt: record.createdAt
            )
        }
    }

    /// 閲覧できる記録（本人 or フレンドの記録）にだけ投稿できる。範囲外はDBのINSERT RLSで拒否される。
    func postComment(storeID: UUID, body: String) async throws -> TimelineComment {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CommentRepositoryError.emptyBody }
        guard trimmed.count <= 500 else { throw CommentRepositoryError.bodyTooLong }
        let userID = try await client.auth.session.user.id
        let record: CommentRecord = try await client.from("comment")
            .insert(CommentInsert(storeID: storeID, userID: userID, body: trimmed))
            .select().single().execute().value
        // 投稿直後も名前・アイコンが「名前未設定」のままにならないよう、自分の情報を取得して埋める。
        let author = try await fetchAuthors([userID]).values.first
        return TimelineComment(
            id: record.id, storeID: record.storeID, userID: record.userID,
            userName: author?.name, avatarURL: author?.avatarURL, body: record.body,
            isMine: true, createdAt: record.createdAt
        )
    }

    /// 本人のコメントのみ削除できる。対象外はDBのDELETE RLSで拒否され0件になる。
    func deleteComment(id: UUID) async throws {
        let deleted: [DeletedCommentID] = try await client.from("comment")
            .delete()
            .eq("id", value: id.uuidString)
            .select("id").execute().value
        guard !deleted.isEmpty else { throw CommentRepositoryError.notFound }
    }

    private func fetchAuthors(_ ids: Set<UUID>) async throws -> [UUID: (name: String?, avatarURL: URL?)] {
        guard !ids.isEmpty else { return [:] }
        let users: [CommentUser] = try await client.from("user")
            .select("id, name, profile_image")
            .in("id", values: ids.map(\.uuidString))
            .execute().value

        var avatarPaths: [UUID: String] = [:]
        for user in users {
            if let path = user.profileImage, !path.isEmpty { avatarPaths[user.id] = path }
        }
        let avatarURLs = try await fetchAvatarURLs(paths: Array(avatarPaths.values))

        return users.reduce(into: [:]) { result, user in
            let name = (user.name?.isEmpty == false) ? user.name : nil
            let avatarURL = avatarPaths[user.id].flatMap { avatarURLs[$0] }
            result[user.id] = (name, avatarURL)
        }
    }

    private func fetchAvatarURLs(paths: [String]) async throws -> [String: URL] {
        guard !paths.isEmpty else { return [:] }
        let results: [SignedURLResult] = try await client.storage.from(profileImagesBucket)
            .createSignedURLs(paths: paths, expiresIn: signedURLExpiresIn)
        return results.reduce(into: [:]) { result, item in
            if let url = item.signedURL { result[item.path] = url }
        }
    }
}

private nonisolated struct CommentUser: Decodable {
    let id: UUID
    let name: String?
    let profileImage: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case profileImage = "profile_image"
    }
}

private nonisolated struct DeletedCommentID: Decodable {
    let id: UUID
}

private nonisolated struct CommentInsert: Encodable {
    let storeID: UUID
    let userID: UUID
    let body: String

    enum CodingKeys: String, CodingKey {
        case body
        case storeID = "store_id"
        case userID = "user_id"
    }
}
