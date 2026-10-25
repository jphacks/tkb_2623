//
//  CommentSheetView.swift
//  GourmetShareMap
//

import SwiftUI

/// タイムラインの記録1件分のコメント一覧と投稿フォーム。
struct CommentSheetView: View {
    let storeName: String
    @State private var viewModel: CommentViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool

    init(storeID: UUID, storeName: String) {
        self.storeName = storeName
        _viewModel = State(initialValue: CommentViewModel(storeID: storeID))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
                Divider().overlay(.appBorder)
                inputBar
            }
            .background(.appBackground)
            .navigationTitle(storeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message) where viewModel.comments.isEmpty:
            ContentUnavailableView {
                Label("読み込めませんでした", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("再読み込み") { Task { await viewModel.load() } }
                    .tint(.appPrimary)
            }
        default:
            commentList
        }
    }

    private var commentList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if viewModel.comments.isEmpty {
                    Text("まだコメントはありません")
                        .font(.system(size: 14))
                        .foregroundStyle(.appText.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }

                ForEach(viewModel.comments) { comment in
                    CommentRow(comment: comment, timeText: viewModel.timeText(for: comment)) {
                        Task { await viewModel.delete(comment) }
                    }
                }
            }
            .padding(16)
        }
        .refreshable { await viewModel.load() }
    }

    private var inputBar: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let message = viewModel.sendErrorMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("コメントを入力", text: $viewModel.draft, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.appCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.appBorder))
                    .focused($isInputFocused)

                Button {
                    Task { await viewModel.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(viewModel.canSend ? .appPrimary : .appText.opacity(0.25))
                }
                .disabled(!viewModel.canSend)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// コメント1件の行。本人のコメントだけ削除ボタンを出す。
private struct CommentRow: View {
    let comment: TimelineComment
    let timeText: String
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            UserInitialAvatar(userID: comment.userID, name: comment.userName, imageURL: comment.avatarURL)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(comment.userName ?? "名前未設定")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.appText)
                    Text(timeText)
                        .font(.system(size: 12))
                        .foregroundStyle(.appText.opacity(0.5))
                }
                Text(comment.body)
                    .font(.system(size: 14))
                    .foregroundStyle(.appText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if comment.isMine {
                Spacer(minLength: 8)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(.appText.opacity(0.4))
                }
            }
        }
    }
}

#Preview {
    CommentSheetView(storeID: UUID(), storeName: "カフェ つむぎ")
}
