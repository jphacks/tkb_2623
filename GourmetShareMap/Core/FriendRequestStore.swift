//
//  FriendRequestStore.swift
//  GourmetShareMap
//

import Foundation
import Observation

/// 自分宛てに届いている承認待ちのフレンド申請を一元管理する。
/// プロフィールタブのバッジとフレンド一覧の「受け取った申請」で同じ状態を共有する。
/// Realtime は使わず、アプリ起動時・フォアグラウンド復帰時・フレンド一覧の表示時・承認/拒否後に取り直す。
@Observable
final class FriendRequestStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// 受け取った申請（新しい順）。
    private(set) var incomingRequests: [FriendRequest] = []
    private(set) var loadState: LoadState = .idle
    /// 申請者のアイコンの署名付きURL（キーは profile-images のパス）。
    private(set) var avatarURLs: [String: URL] = [:]
    /// 承認・拒否の通信中の申請者ID。ボタンの二重押しを防ぐ。
    private(set) var processingRequesterIDs: Set<UUID> = []
    /// 承認・拒否に失敗したときのメッセージ。
    var actionErrorMessage: String?

    private let repository: any FriendDataSource

    /// 引数を省略すると Supabase に接続する本番の Repository を使う。
    init(repository: (any FriendDataSource)? = nil) {
        self.repository = repository ?? FriendRepository()
    }

    /// プロフィールタブのバッジに出す件数。
    var incomingCount: Int { incomingRequests.count }

    func refresh() async {
        loadState = .loading
        do {
            let requests = try await repository.fetchIncomingRequests()
            incomingRequests = requests
            loadState = .loaded
            avatarURLs = await repository.avatarURLs(for: requests.compactMap(\.requester.profileImage))
        } catch {
            // 取得に失敗しても、直前に取得できていた一覧とバッジは残す。
            loadState = .failed(error.localizedDescription)
        }
    }

    /// 申請を承認する。成功したら true を返す（呼び出し側でフレンド一覧を再読込する）。
    @discardableResult
    func accept(_ request: FriendRequest) async -> Bool {
        await process(request) { try await repository.acceptRequest(from: request.requester.id) }
    }

    /// 申請を拒否する。成功したら true を返す。
    @discardableResult
    func reject(_ request: FriendRequest) async -> Bool {
        await process(request) { try await repository.rejectRequest(from: request.requester.id) }
    }

    private func process(_ request: FriendRequest, action: () async throws -> Void) async -> Bool {
        let requesterID = request.requester.id
        guard !processingRequesterIDs.contains(requesterID) else { return false }
        processingRequesterIDs.insert(requesterID)
        actionErrorMessage = nil
        defer { processingRequesterIDs.remove(requesterID) }

        do {
            try await action()
        } catch {
            actionErrorMessage = error.localizedDescription
            // 申請が取り消し済みなど、一覧が古い可能性があるので取り直す。
            await refresh()
            return false
        }
        await refresh()
        return true
    }
}
