//
//  BlockedUsersViewModelTests.swift
//  GourmetShareMapTests
//

import Foundation
import Testing
@testable import GourmetShareMap

@MainActor
final class FakeBlockedUsersFetcher: BlockedUsersFetching {
    var users: [BlockedUser] = []
    var fetchError: (any Error)?
    var unblockError: (any Error)?
    private(set) var unblockedUserIDs: [UUID] = []

    func fetchBlockedUsers() async throws -> [BlockedUser] {
        if let fetchError { throw fetchError }
        return users
    }

    func unblock(userID: UUID) async throws {
        if let unblockError { throw unblockError }
        unblockedUserIDs.append(userID)
    }
}

@MainActor
struct BlockedUsersViewModelTests {
    private func user(_ name: String) -> BlockedUser {
        BlockedUser(id: UUID(), name: name, createdAt: .now)
    }

    @Test func 読み込みに成功したら一覧を保持する() async {
        let fetcher = FakeBlockedUsersFetcher()
        fetcher.users = [user("太郎"), user("花子")]
        let viewModel = BlockedUsersViewModel(repository: fetcher)

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.users.map(\.name) == ["太郎", "花子"])
    }

    @Test func 読み込みに失敗したら失敗状態になる() async {
        let fetcher = FakeBlockedUsersFetcher()
        fetcher.fetchError = URLError(.notConnectedToInternet)
        let viewModel = BlockedUsersViewModel(repository: fetcher)

        await viewModel.load()

        guard case .failed = viewModel.loadState else {
            Issue.record("失敗状態になっていない: \(viewModel.loadState)")
            return
        }
    }

    @Test func 解除に成功したら一覧から取り除く() async {
        let fetcher = FakeBlockedUsersFetcher()
        let target = user("太郎")
        fetcher.users = [target, user("花子")]
        let viewModel = BlockedUsersViewModel(repository: fetcher)
        await viewModel.load()

        await viewModel.unblock(target)

        #expect(fetcher.unblockedUserIDs == [target.id])
        #expect(viewModel.users.map(\.name) == ["花子"])
        #expect(viewModel.errorMessage == nil)
    }

    @Test func 解除に失敗したらエラーを保持し一覧は残す() async {
        let fetcher = FakeBlockedUsersFetcher()
        let target = user("太郎")
        fetcher.users = [target]
        fetcher.unblockError = URLError(.notConnectedToInternet)
        let viewModel = BlockedUsersViewModel(repository: fetcher)
        await viewModel.load()

        await viewModel.unblock(target)

        #expect(viewModel.users.map(\.name) == ["太郎"])
        #expect(viewModel.errorMessage != nil)
    }
}
