//
//  BlockedUsersView.swift
//  GourmetShareMap
//

import SwiftUI

/// プロフィール画面から開く、ブロック中のユーザー一覧。ここから解除もできる。
struct BlockedUsersView: View {
    @State private var viewModel = BlockedUsersViewModel()
    @State private var pendingUnblock: BlockedUser?

    private let accentOrange = Color(red: 0.76, green: 0.35, blue: 0.22)

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("ブロック中のユーザー")
                .navigationBarTitleDisplayMode(.inline)
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("読み込めませんでした", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("再読み込み") { Task { await viewModel.load() } }
                    .tint(accentOrange)
            }
        case .loaded:
            if viewModel.users.isEmpty {
                ContentUnavailableView(
                    "ブロックしているユーザーはいません",
                    systemImage: "hand.raised.slash"
                )
            } else {
                list
            }
        }
    }

    private var list: some View {
        List(viewModel.users) { user in
            HStack(spacing: 12) {
                UserInitialAvatar(userID: user.id, name: user.name)
                Text(user.name ?? "名前未設定")
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                Button("解除") { pendingUnblock = user }
                    .buttonStyle(.bordered)
                    .tint(accentOrange)
            }
        }
        .confirmationDialog(
            "\(pendingUnblock?.name ?? "このユーザー")のブロックを解除しますか？",
            isPresented: Binding(
                get: { pendingUnblock != nil },
                set: { isPresented in if !isPresented { pendingUnblock = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("解除する") {
                if let user = pendingUnblock { Task { await viewModel.unblock(user) } }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert(
            "解除に失敗しました",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { isPresented in if !isPresented { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

#Preview {
    BlockedUsersView()
}
