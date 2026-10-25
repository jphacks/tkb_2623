import Foundation
import Supabase

@MainActor
final class TimelineRepository {
    private let client: SupabaseClient
    private let imageRepository: ImageRepository
    private let profileImagesBucket = "profile-images"
    private let signedURLExpiresIn = 3600

    init(client: SupabaseClient) {
        self.client = client
        self.imageRepository = ImageRepository(client: client)
    }
    convenience init() { self.init(client: SupabaseManager.shared.client) }

    /// `since` 以降に登録された、自分とフォロー中フレンドの店舗記録を新しい順に返す。
    /// どの行が見えるかは store の RLS（自分 + フォロー中）に任せる。
    func fetchFeed(since: Date) async throws -> TimelineFeed {
        let userID = try await client.auth.session.user.id

        async let storesTask: [StoreRecord] = client.from("store")
            .select()
            .gte("created_at", value: since.ISO8601Format())
            .order("created_at", ascending: false)
            .order("id", ascending: true)
            .execute().value
        async let friendCountTask = fetchFriendCount(userID: userID)

        let stores = try await storesTask
        let friendCount = try await friendCountTask

        async let usersTask = fetchUsers(Set(stores.map(\.userID)))
        async let coverURLsTask = imageRepository.coverImageURLs(
            storeIDs: stores.map(\.id), expiresIn: signedURLExpiresIn
        )
        async let commentCountsTask = fetchCommentCounts(storeIDs: stores.map(\.id))
        async let likeStatesTask = fetchLikeStates(storeIDs: stores.map(\.id), currentUserID: userID)
        let users = try await usersTask
        let coverURLs = try await coverURLsTask
        let commentCounts = try await commentCountsTask
        let likeStates = try await likeStatesTask
        let avatarURLs = await fetchAvatarURLs(users)

        let posts = stores.map { store in
            let name = users[store.userID]?.name
            return TimelinePost(
                id: store.id,
                storeName: store.name,
                category: store.category,
                memo: store.memo,
                userID: store.userID,
                userName: name?.isEmpty == false ? name : nil,
                userAvatarURL: avatarURLs[store.userID],
                isMine: store.userID == userID,
                createdAt: store.createdAt,
                coverImageURL: coverURLs[store.id],
                commentCount: commentCounts[store.id] ?? 0,
                likeCount: likeStates[store.id]?.count ?? 0,
                isLikedByMe: likeStates[store.id]?.isMine ?? false
            )
        }
        return TimelineFeed(posts: posts, friendCount: friendCount)
    }

    private func fetchFriendCount(userID: UUID) async throws -> Int {
        // friend の RLS はフォロワー側の行も返すため、自分がフォローしている行に絞る。
        try await client.from("friend")
            .select("*", head: true, count: .exact)
            .eq("user_id", value: userID)
            .execute().count ?? 0
    }

    private func fetchUsers(_ ids: Set<UUID>) async throws -> [UUID: TimelineUser] {
        guard !ids.isEmpty else { return [:] }
        let users: [TimelineUser] = try await client.from("user")
            .select("id, name, profile_image")
            .in("id", values: ids.map(\.uuidString))
            .execute().value
        return Dictionary(users.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// アイコン画像の署名付きURL。アイコンは表示の補助なので、取得に失敗してもフィード全体は失敗させず、
    /// 頭文字のアイコンにフォールバックさせる。
    private func fetchAvatarURLs(_ users: [UUID: TimelineUser]) async -> [UUID: URL] {
        let paths = users.compactMapValues { user in
            user.profileImage.flatMap { $0.isEmpty ? nil : $0 }
        }
        guard !paths.isEmpty else { return [:] }

        do {
            let results: [SignedURLResult] = try await client.storage.from(profileImagesBucket)
                .createSignedURLs(paths: Array(Set(paths.values)), expiresIn: signedURLExpiresIn)
            let urlsByPath = results.reduce(into: [String: URL]()) { result, item in
                if let url = item.signedURL { result[item.path] = url }
            }
            return paths.compactMapValues { urlsByPath[$0] }
        } catch {
            return [:]
        }
    }

    /// 店舗ごとのコメント件数。本文は使わないので store_id だけ取得してクライアント側で数える。
    private func fetchCommentCounts(storeIDs: [UUID]) async throws -> [UUID: Int] {
        guard !storeIDs.isEmpty else { return [:] }
        let rows: [CommentStoreID] = try await client.from("comment")
            .select("store_id")
            .in("store_id", values: storeIDs.map(\.uuidString))
            .execute().value
        return rows.reduce(into: [:]) { counts, row in
            counts[row.storeID, default: 0] += 1
        }
    }

    /// 店舗ごとのいいね件数と、自分がいいね済みかどうか。
    private func fetchLikeStates(storeIDs: [UUID], currentUserID: UUID) async throws -> [UUID: LikeState] {
        guard !storeIDs.isEmpty else { return [:] }
        let rows: [StoreLikeRow] = try await client.from("store_like")
            .select("store_id, user_id")
            .in("store_id", values: storeIDs.map(\.uuidString))
            .execute().value

        var counts: [UUID: Int] = [:]
        var likedByMe: Set<UUID> = []
        for row in rows {
            counts[row.storeID, default: 0] += 1
            if row.userID == currentUserID { likedByMe.insert(row.storeID) }
        }
        return counts.reduce(into: [:]) { result, pair in
            result[pair.key] = LikeState(count: pair.value, isMine: likedByMe.contains(pair.key))
        }
    }
}

private nonisolated struct LikeState {
    let count: Int
    let isMine: Bool
}

private nonisolated struct TimelineUser: Decodable {
    let id: UUID
    let name: String?
    let profileImage: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case profileImage = "profile_image"
    }
}

private nonisolated struct CommentStoreID: Decodable {
    let storeID: UUID
    enum CodingKeys: String, CodingKey { case storeID = "store_id" }
}

private nonisolated struct StoreLikeRow: Decodable {
    let storeID: UUID
    let userID: UUID
    enum CodingKeys: String, CodingKey {
        case storeID = "store_id"
        case userID = "user_id"
    }
}
