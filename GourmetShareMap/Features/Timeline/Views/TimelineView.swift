//
//  TimelineView.swift
//  GourmetShareMap
//

import SwiftUI

/// 08 タイムライン。自分とフレンドの直近 3 日間の記録を新しい順に並べる。
struct TimelineView: View {
    var onFindFriends: () -> Void = {}
    var onCreateRecord: () -> Void = {}

    @Environment(RecordStore.self) private var recordStore
    @State private var viewModel = TimelineViewModel()
    @State private var commentPost: TimelinePost?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(.appBorder)
            content
        }
        .background(.appBackground)
        // 表示時と、自分の記録を登録・更新したあとに取り直す。
        .task(id: recordStore.records) { await viewModel.load() }
        .sheet(item: $commentPost) { post in
            CommentSheetView(storeID: post.id, storeName: post.storeName)
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("タイムライン")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(.appText)
                Spacer()
                Text("フレンド \(viewModel.friendCount)人")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.appText.opacity(0.7))
            }

            TimelineFilterControl(selection: $viewModel.filter)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message) where viewModel.posts.isEmpty:
            ContentUnavailableView {
                Label("読み込めませんでした", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("再読み込み") { Task { await viewModel.load() } }
                    .tint(.appPrimary)
            }
        default:
            if viewModel.showsNoFriendsState {
                TimelineNoFriendsView(onFindFriends: onFindFriends, onCreateRecord: onCreateRecord)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                postList
            }
        }
    }

    private var postList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if viewModel.sections.isEmpty {
                    Text("直近\(TimelineViewModel.dayRange)日間の記録はありません")
                        .font(.system(size: 14))
                        .foregroundStyle(.appText.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }

                ForEach(viewModel.sections) { section in
                    Text(section.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.appText.opacity(0.7))
                        .padding(.top, 8)

                    ForEach(section.posts) { post in
                        TimelinePostCard(
                            post: post,
                            timeText: viewModel.timeText(for: post),
                            onTapLike: { Task { await viewModel.toggleLike(for: post) } }
                        ) {
                            commentPost = post
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .refreshable { await viewModel.load() }
    }
}

#Preview {
    TimelineView()
        .environment(RecordStore())
}
