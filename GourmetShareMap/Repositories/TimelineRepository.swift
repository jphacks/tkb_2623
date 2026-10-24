import Foundation
import Supabase

@MainActor
final class TimelineRepository {
    private let client: SupabaseClient
    private let imageBucket = "record-images"
    private let signedURLExpiresIn = 3600

    init(client: SupabaseClient) { self.client = client }
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

        async let namesTask = fetchUserNames(Set(stores.map(\.userID)))
        async let coverURLsTask = fetchCoverImageURLs(storeIDs: stores.map(\.id))
        let names = try await namesTask
        let coverURLs = try await coverURLsTask

        let posts = stores.map { store in
            TimelinePost(
                id: store.id,
                storeName: store.name,
                category: store.category,
                userID: store.userID,
                userName: names[store.userID],
                isMine: store.userID == userID,
                createdAt: store.createdAt,
                coverImageURL: coverURLs[store.id]
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

    private func fetchUserNames(_ ids: Set<UUID>) async throws -> [UUID: String] {
        guard !ids.isEmpty else { return [:] }
        let users: [TimelineUser] = try await client.from("user")
            .select("id, name")
            .in("id", values: ids.map(\.uuidString))
            .execute().value
        return users.reduce(into: [:]) { result, user in
            if let name = user.name, !name.isEmpty { result[user.id] = name }
        }
    }

    /// 店舗ごとに最初にアップロードされた写真（表紙）の署名付きURL。
    private func fetchCoverImageURLs(storeIDs: [UUID]) async throws -> [UUID: URL] {
        guard !storeIDs.isEmpty else { return [:] }
        let images: [ImageRecord] = try await client.from("image")
            .select()
            .in("store_id", values: storeIDs.map(\.uuidString))
            .order("created_at", ascending: true)
            .execute().value

        var coverPaths: [UUID: String] = [:]
        for image in images where coverPaths[image.storeID] == nil {
            coverPaths[image.storeID] = image.path
        }
        guard !coverPaths.isEmpty else { return [:] }

        let results: [SignedURLResult] = try await client.storage.from(imageBucket)
            .createSignedURLs(paths: Array(coverPaths.values), expiresIn: signedURLExpiresIn)
        let urlsByPath = results.reduce(into: [String: URL]()) { result, item in
            if let url = item.signedURL { result[item.path] = url }
        }
        return coverPaths.compactMapValues { urlsByPath[$0] }
    }
}

private nonisolated struct TimelineUser: Decodable {
    let id: UUID
    let name: String?
}
