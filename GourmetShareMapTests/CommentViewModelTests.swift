//
//  CommentViewModelTests.swift
//  GourmetShareMapTests
//

import Foundation
import Testing
@testable import GourmetShareMap

@MainActor
final class FakeCommentFetcher: CommentFetching {
    var comments: [TimelineComment] = []
    var fetchError: (any Error)?
    var postError: (any Error)?
    var deleteError: (any Error)?
    private(set) var deletedIDs: [UUID] = []

    func fetchComments(storeID: UUID) async throws -> [TimelineComment] {
        if let fetchError { throw fetchError }
        return comments
    }

    func postComment(storeID: UUID, body: String) async throws -> TimelineComment {
        if let postError { throw postError }
        let comment = TimelineComment(
            id: UUID(), storeID: storeID, userID: UUID(), userName: "自分", avatarURL: nil,
            body: body, isMine: true, createdAt: .now
        )
        comments.append(comment)
        return comment
    }

    func deleteComment(id: UUID) async throws {
        if let deleteError { throw deleteError }
        deletedIDs.append(id)
    }
}

@MainActor
struct CommentViewModelTests {
    private func comment(_ body: String, isMine: Bool, createdAt: Date = .now) -> TimelineComment {
        TimelineComment(
            id: UUID(), storeID: UUID(), userID: UUID(), userName: "あおい", avatarURL: nil,
            body: body, isMine: isMine, createdAt: createdAt
        )
    }

    @Test func 読み込んだコメントを一覧に反映する() async {
        let fetcher = FakeCommentFetcher()
        fetcher.comments = [comment("おいしかった", isMine: false)]
        let viewModel = CommentViewModel(storeID: UUID(), repository: fetcher)

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.comments.map(\.body) == ["おいしかった"])
    }

    @Test func 読み込み失敗で失敗状態になる() async {
        let fetcher = FakeCommentFetcher()
        fetcher.fetchError = URLError(.notConnectedToInternet)
        let viewModel = CommentViewModel(storeID: UUID(), repository: fetcher)

        await viewModel.load()

        guard case .failed = viewModel.loadState else {
            Issue.record("失敗状態になっていない: \(viewModel.loadState)")
            return
        }
    }

    @Test func 空白のみの入力は送信できない() {
        let viewModel = CommentViewModel(storeID: UUID(), repository: FakeCommentFetcher())
        viewModel.draft = "   "
        #expect(!viewModel.canSend)
    }

    @Test func 送信すると一覧に追加され入力欄がクリアされる() async {
        let fetcher = FakeCommentFetcher()
        let viewModel = CommentViewModel(storeID: UUID(), repository: fetcher)
        viewModel.draft = "行ってみたい"

        await viewModel.send()

        #expect(viewModel.comments.map(\.body) == ["行ってみたい"])
        #expect(viewModel.draft == "")
        #expect(viewModel.sendErrorMessage == nil)
    }

    @Test func 送信失敗時は入力欄を残してエラーを表示する() async {
        let fetcher = FakeCommentFetcher()
        fetcher.postError = URLError(.notConnectedToInternet)
        let viewModel = CommentViewModel(storeID: UUID(), repository: fetcher)
        viewModel.draft = "行ってみたい"

        await viewModel.send()

        #expect(viewModel.comments.isEmpty)
        #expect(viewModel.draft == "行ってみたい")
        #expect(viewModel.sendErrorMessage != nil)
    }

    @Test func 削除に成功すると一覧から消える() async {
        let fetcher = FakeCommentFetcher()
        let target = comment("消すコメント", isMine: true)
        fetcher.comments = [target]
        let viewModel = CommentViewModel(storeID: UUID(), repository: fetcher)
        await viewModel.load()

        await viewModel.delete(target)

        #expect(viewModel.comments.isEmpty)
        #expect(fetcher.deletedIDs == [target.id])
    }

    @Test func 削除に失敗すると一覧に残る() async {
        let fetcher = FakeCommentFetcher()
        let target = comment("他人のコメント", isMine: false)
        fetcher.comments = [target]
        fetcher.deleteError = CommentRepositoryError.notFound
        let viewModel = CommentViewModel(storeID: UUID(), repository: fetcher)
        await viewModel.load()

        await viewModel.delete(target)

        #expect(viewModel.comments.map(\.id) == [target.id])
        #expect(viewModel.sendErrorMessage != nil)
    }

    @Test func 経過時間の表示は端末の言語設定に関わらず日本語() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let viewModel = CommentViewModel(storeID: UUID(), repository: FakeCommentFetcher(), now: { now })

        #expect(viewModel.timeText(for: comment("a", isMine: true, createdAt: now.addingTimeInterval(-30))) == "たった今")
        #expect(viewModel.timeText(for: comment("a", isMine: true, createdAt: now.addingTimeInterval(-60 * 5))) == "5分前")
        #expect(viewModel.timeText(for: comment("a", isMine: true, createdAt: now.addingTimeInterval(-3600 * 2))) == "2時間前")
        #expect(viewModel.timeText(for: comment("a", isMine: true, createdAt: now.addingTimeInterval(-86400 * 3))) == "3日前")
    }
}
