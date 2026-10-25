//
//  BlockedUsersViewModel.swift
//  GourmetShareMap
//

import Foundation
import Observation

/// ブロック中ユーザー一覧の取得・解除（`BlockRepository`）。テストで差し替えられるようにプロトコルにしている。
protocol BlockedUsersFetching {
    func fetchBlockedUsers() async throws -> [BlockedUser]
    func unblock(userID: UUID) async throws
}

extension BlockRepository: BlockedUsersFetching {}

@Observable
final class BlockedUsersViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var users: [BlockedUser] = []
    private(set) var loadState: LoadState = .idle
    /// 解除操作の失敗メッセージ。Viewが確認後にnilへ戻す。
    var errorMessage: String?

    private let repository: any BlockedUsersFetching

    /// 引数を省略すると Supabase に接続する本番の Repository を使う。
    init(repository: (any BlockedUsersFetching)? = nil) {
        self.repository = repository ?? BlockRepository()
    }

    func load() async {
        loadState = .loading
        do {
            users = try await repository.fetchBlockedUsers()
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// ブロックを解除する。成功したら一覧からその場で取り除く。
    func unblock(_ user: BlockedUser) async {
        errorMessage = nil
        do {
            try await repository.unblock(userID: user.id)
            users.removeAll { $0.id == user.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
