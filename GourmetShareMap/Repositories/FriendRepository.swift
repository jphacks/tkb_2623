//
//  FriendRepository.swift
//  GourmetShareMap
//

import Foundation
import Supabase

/// フレンド関連のDBエラーを、画面に出せるアプリのエラーに変換したもの。
/// DB関数（send_friend_request など）が返す SQLSTATE は supabase/migrations/20261024150100_friend_request.sql を参照。
nonisolated enum FriendRepositoryError: LocalizedError, Equatable {
    case invalidUserName
    case cannotRequestSelf
    case alreadyFriends
    /// 承認しようとした申請が取り消し済み・処理済み。
    case requestNotFound
    case userNotFound
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .invalidUserName: return UserName.formatMessage
        case .cannotRequestSelf: return "自分自身にはフレンド申請できません。"
        case .alreadyFriends: return "既にフレンドです。"
        case .requestNotFound: return "この申請は取り消されたか、既に処理されています。"
        case .userNotFound: return "ユーザーが見つかりませんでした。"
        case .unexpectedResponse: return "サーバーから予期しない応答がありました。"
        }
    }

    /// DB関数のエラーコードに対応するものは変換し、それ以外（通信・認証エラーなど）はそのまま返す。
    static func map(_ error: any Error) -> any Error {
        guard let postgrestError = error as? PostgrestError else { return error }
        switch postgrestError.code {
        case "GSF01": return FriendRepositoryError.cannotRequestSelf
        case "GSF02": return FriendRepositoryError.alreadyFriends
        case "GSF04": return FriendRepositoryError.requestNotFound
        case "GSF05": return FriendRepositoryError.userNotFound
        default: return error
        }
    }
}

/// フレンド一覧・申請・検索の読み書き口。画面側はこのプロトコルに依存し、テストではフェイクに差し替える。
protocol FriendDataSource {
    /// 自分がフォローしている（friend.user_id = 自分の）相手の一覧。
    func fetchFriends() async throws -> [FriendUser]
    /// 自分宛てに届いている承認待ちの申請（新しい順）。
    func fetchIncomingRequests() async throws -> [FriendRequest]
    /// user_name の完全一致検索。見つからなければ nil。形式違反の入力は通信せずに throw する。
    func searchUser(userName: String) async throws -> FriendSearchResult?
    /// フレンド申請する。相手から申請が来ていれば、その場で承認扱いになる。
    func sendRequest(to userID: UUID) async throws -> FriendRequestSendResult
    /// 自分宛ての申請を承認する（相互フレンドになる）。
    func acceptRequest(from requesterID: UUID) async throws
    /// 自分宛ての申請を拒否する（申請を削除する）。
    func rejectRequest(from requesterID: UUID) async throws
    /// profile-images のパスから表示用の署名付きURLを取得する。取得できなかったパスは結果に含めない。
    func avatarURLs(for paths: [String]) async -> [String: URL]
}

@MainActor
final class FriendRepository: FriendDataSource {
    private let client: SupabaseClient
    private let profileImagesBucket = "profile-images"
    private let signedURLExpiresIn = 3600

    /// 相手の user 行から取得する列。FriendUser に対応する。
    private let userColumns = "id, user_name, name, profile_image"

    init(client: SupabaseClient) { self.client = client }
    convenience init() { self.init(client: SupabaseManager.shared.client) }

    func fetchFriends() async throws -> [FriendUser] {
        let userID = try await client.auth.session.user.id

        // friend の RLS はフォロワー側の行も返すため、自分がフォローしている行に絞る。
        // 相手の user 行は「user: select followed users」ポリシーで参照できる。
        let rows: [FriendRow] = try await client.from("friend")
            .select("created_at, friend:user!friend_friend_id_fkey(\(userColumns))")
            .eq("user_id", value: userID)
            .order("created_at", ascending: false)
            .execute().value
        return rows.compactMap(\.friend)
    }

    /// 自分がフォローしている相手の人数。行は取得せず件数だけを数える。
    func fetchFriendCount() async throws -> Int {
        let userID = try await client.auth.session.user.id

        // friend の RLS はフォロワー側の行も返すため、自分がフォローしている行に絞る。
        return try await client.from("friend")
            .select("*", head: true, count: .exact)
            .eq("user_id", value: userID)
            .execute().count ?? 0
    }

    func fetchIncomingRequests() async throws -> [FriendRequest] {
        let userID = try await client.auth.session.user.id

        // 申請者の user 行は「user: select requesters」ポリシーで参照できる。
        let rows: [IncomingRequestRow] = try await client.from("friend_request")
            .select("created_at, requester:user!friend_request_requester_id_fkey(\(userColumns))")
            .eq("addressee_id", value: userID)
            .order("created_at", ascending: false)
            .execute().value
        return rows.compactMap { row in
            row.requester.map { FriendRequest(requester: $0, createdAt: row.createdAt) }
        }
    }

    func searchUser(userName: String) async throws -> FriendSearchResult? {
        let normalized = UserName.normalize(userName)
        guard UserName.isValid(normalized) else { throw FriendRepositoryError.invalidUserName }
        _ = try await client.auth.session

        let rows: [SearchRow] = try await client
            .rpc("search_user_by_user_name", params: ["p_user_name": normalized])
            .execute().value
        return rows.first.map { row in
            FriendSearchResult(
                user: FriendUser(id: row.id, userName: row.userName, name: row.name, profileImage: row.profileImage),
                relation: row.relation
            )
        }
    }

    func sendRequest(to userID: UUID) async throws -> FriendRequestSendResult {
        _ = try await client.auth.session
        do {
            let result: String = try await client
                .rpc("send_friend_request", params: ["p_addressee_id": userID])
                .execute().value
            guard let sendResult = FriendRequestSendResult(rawValue: result) else {
                throw FriendRepositoryError.unexpectedResponse
            }
            return sendResult
        } catch {
            throw FriendRepositoryError.map(error)
        }
    }

    func acceptRequest(from requesterID: UUID) async throws {
        _ = try await client.auth.session
        do {
            try await client
                .rpc("accept_friend_request", params: ["p_requester_id": requesterID])
                .execute()
        } catch {
            throw FriendRepositoryError.map(error)
        }
    }

    func rejectRequest(from requesterID: UUID) async throws {
        let userID = try await client.auth.session.user.id

        // 申請が既に取り消されていても（削除0件でも）エラーにはしない。
        try await client.from("friend_request")
            .delete()
            .eq("requester_id", value: requesterID)
            .eq("addressee_id", value: userID)
            .execute()
    }

    func avatarURLs(for paths: [String]) async -> [String: URL] {
        let uniquePaths = Array(Set(paths))
        guard !uniquePaths.isEmpty else { return [:] }
        // アイコンは補助的な表示なので、取得に失敗しても画面全体のエラーにはしない（固定アイコンで表示する）。
        guard let results = try? await client.storage.from(profileImagesBucket)
            .createSignedURLs(paths: uniquePaths, expiresIn: signedURLExpiresIn)
        else { return [:] }
        return results.reduce(into: [:]) { result, item in
            if let url = item.signedURL { result[item.path] = url }
        }
    }
}

private nonisolated struct FriendRow: Decodable {
    /// RLSで相手の user 行が見えない場合は null になる。
    let friend: FriendUser?
}

private nonisolated struct IncomingRequestRow: Decodable {
    let createdAt: Date
    let requester: FriendUser?

    enum CodingKeys: String, CodingKey {
        case requester
        case createdAt = "created_at"
    }
}

private nonisolated struct SearchRow: Decodable {
    let id: UUID
    let userName: String
    let name: String?
    let profileImage: String?
    let relation: FriendRelation

    enum CodingKeys: String, CodingKey {
        case id, name, relation
        case userName = "user_name"
        case profileImage = "profile_image"
    }
}
