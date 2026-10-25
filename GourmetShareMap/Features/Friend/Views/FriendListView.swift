//
//  FriendListView.swift
//  GourmetShareMap
//

import SwiftUI

/// フレンド関連画面の遷移先。プロフィールタブの NavigationStack で使う。
enum FriendRoute: Hashable {
    case list
    case add
}

/// フレンド一覧。上部に受け取った申請（承認・拒否）、その下にフレンドを並べる。
struct FriendListView: View {
    @Environment(FriendRequestStore.self) private var requestStore
    @State private var viewModel = FriendListViewModel()
    /// タップされたフレンド。タイムラインと同じ`FriendProfileView`をシート表示する。
    @State private var selectedFriend: FriendUser?

    var body: some View {
        List {
            if !requestStore.incomingRequests.isEmpty {
                incomingRequestsSection
            }
            friendsSection
        }
        .scrollContentBackground(.hidden)
        .background(.appBackground)
        .navigationTitle("フレンド")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: FriendRoute.add) {
                    Label("フレンド追加", systemImage: "person.badge.plus")
                }
                .tint(.appPrimary)
            }
        }
        .sheet(item: $selectedFriend) { friend in
            FriendProfileView(userID: friend.id)
        }
        // 表示のたびに（フレンド追加画面から戻ったときも）一覧と受信申請を取り直す。
        .task { await reload() }
        .refreshable { await reload() }
        .alert(
            "処理できませんでした",
            isPresented: Binding(
                get: { requestStore.actionErrorMessage != nil },
                set: { if !$0 { requestStore.actionErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(requestStore.actionErrorMessage ?? "")
        }
    }

    private var incomingRequestsSection: some View {
        Section("受け取った申請") {
            ForEach(requestStore.incomingRequests) { request in
                IncomingFriendRequestRow(
                    request: request,
                    avatarURL: request.requester.profileImage.flatMap { requestStore.avatarURLs[$0] },
                    isProcessing: requestStore.processingRequesterIDs.contains(request.requester.id),
                    onAccept: { Task { await accept(request) } },
                    onReject: { Task { await requestStore.reject(request) } }
                )
            }
        }
    }

    @ViewBuilder
    private var friendsSection: some View {
        Section("フレンド \(viewModel.friends.count)人") {
            switch viewModel.loadState {
            // 再読込中は直前の一覧を出したままにし、初回の読み込みだけインジケーターを出す。
            case .idle:
                loadingRow
            case .loading where viewModel.friends.isEmpty:
                loadingRow
            case .failed(let message) where viewModel.friends.isEmpty:
                ContentUnavailableView {
                    Label("読み込めませんでした", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("再読み込み") { Task { await viewModel.load() } }
                        .tint(.appPrimary)
                }
            default:
                if viewModel.friends.isEmpty {
                    emptyView
                } else {
                    ForEach(viewModel.friends) { friend in
                        Button {
                            selectedFriend = friend
                        } label: {
                            FriendUserRow(user: friend, avatarURL: viewModel.avatarURL(for: friend)) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.appText.opacity(0.3))
                            }
                            // 行の余白部分をタップしても反応させる。
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var loadingRow: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("フレンドがまだいません", systemImage: "person.2")
        } description: {
            Text("ユーザー名で検索して、フレンド申請を送ってみましょう。")
        } actions: {
            NavigationLink(value: FriendRoute.add) {
                Text("フレンドを追加する")
                    .font(.system(size: 15, weight: .bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.appPrimary)
        }
    }

    private func reload() async {
        async let friends: Void = viewModel.load()
        async let requests: Void = requestStore.refresh()
        _ = await (friends, requests)
    }

    private func accept(_ request: FriendRequest) async {
        if await requestStore.accept(request) {
            await viewModel.load()
        }
    }
}

#Preview {
    NavigationStack {
        FriendListView()
    }
    .environment(FriendRequestStore())
}
