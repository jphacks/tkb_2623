//
//  CommentViewModel.swift
//  GourmetShareMap
//

import Foundation
import Observation

/// コメントの取得・投稿・削除（`CommentRepository`）。テストで差し替えられるようにプロトコルにしている。
protocol CommentFetching {
    func fetchComments(storeID: UUID) async throws -> [TimelineComment]
    func postComment(storeID: UUID, body: String) async throws -> TimelineComment
    func deleteComment(id: UUID) async throws
}

extension CommentRepository: CommentFetching {}

@Observable
final class CommentViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let storeID: UUID
    var draft: String = ""
    private(set) var comments: [TimelineComment] = []
    private(set) var loadState: LoadState = .idle
    private(set) var isSending = false
    private(set) var sendErrorMessage: String?

    private let repository: any CommentFetching
    private let now: () -> Date

    init(storeID: UUID, repository: (any CommentFetching)? = nil, now: @escaping () -> Date = { .now }) {
        self.storeID = storeID
        self.repository = repository ?? CommentRepository()
        self.now = now
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    func load() async {
        if comments.isEmpty { loadState = .loading }
        do {
            comments = try await repository.fetchComments(storeID: storeID)
            loadState = .loaded
        } catch is CancellationError {
            if loadState == .loading { loadState = .idle }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// 送信に成功したら入力欄をクリアし、一覧末尾に追加する。
    func send() async {
        let body = draft
        guard canSend else { return }
        isSending = true
        sendErrorMessage = nil
        defer { isSending = false }
        do {
            let comment = try await repository.postComment(storeID: storeID, body: body)
            comments.append(comment)
            draft = ""
        } catch {
            sendErrorMessage = error.localizedDescription
        }
    }

    /// 削除に失敗したとき（他人のコメントなど）は一覧から取り除かない。
    func delete(_ comment: TimelineComment) async {
        do {
            try await repository.deleteComment(id: comment.id)
            comments.removeAll { $0.id == comment.id }
        } catch {
            sendErrorMessage = error.localizedDescription
        }
    }

    /// 投稿時刻の相対表示。端末の言語設定に左右されないよう、他の画面と同じく日本語を自前で組み立てる。
    func timeText(for comment: TimelineComment) -> String {
        let minutes = max(0, Int(now().timeIntervalSince(comment.createdAt) / 60))
        if minutes < 1 { return "たった今" }
        if minutes < 60 { return "\(minutes)分前" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)時間前" }
        return "\(hours / 24)日前"
    }
}
