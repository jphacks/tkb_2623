//
//  FriendListViewModel.swift
//  GourmetShareMap
//

import Foundation
import Observation

/// フレンド一覧画面。受け取った申請は FriendRequestStore が持ち、ここではフレンドの一覧だけを扱う。
@Observable
final class FriendListViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var friends: [FriendUser] = []
    private(set) var loadState: LoadState = .idle
    /// フレンドのアイコンの署名付きURL（キーは profile-images のパス）。
    private(set) var avatarURLs: [String: URL] = [:]

    private let repository: any FriendDataSource

    /// 引数を省略すると Supabase に接続する本番の Repository を使う。
    init(repository: (any FriendDataSource)? = nil) {
        self.repository = repository ?? FriendRepository()
    }

    func load() async {
        loadState = .loading
        do {
            let fetched = try await repository.fetchFriends()
            friends = fetched
            loadState = .loaded
            avatarURLs = await repository.avatarURLs(for: fetched.compactMap(\.profileImage))
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func avatarURL(for user: FriendUser) -> URL? {
        user.profileImage.flatMap { avatarURLs[$0] }
    }
}
