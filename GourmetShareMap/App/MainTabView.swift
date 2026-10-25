//
//  MainTabView.swift
//  GourmetShareMap
//

import SwiftUI

struct MainTabView: View {
    enum TabItem: Hashable {
        case grow, map, record, timeline, profile
    }

    @State private var recordStore = RecordStore()
    @State private var friendRequestStore = FriendRequestStore()
    @State private var selectedTab: TabItem = .map
    @State private var isPresentingFriendAdd = false
    @Environment(\.scenePhase) private var scenePhase
    private let accentOrange = Color(red: 0.76, green: 0.35, blue: 0.22)

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("育てる", systemImage: "sparkles", value: .grow) {
                GrowView()
            }

            Tab("マップ", systemImage: "map", value: .map) {
                MapView(onCreateRecord: { selectedTab = .record })
            }

            Tab("登録", systemImage: "camera", value: .record) {
                RecordCreateView(
                    isActive: selectedTab == .record,
                    onShowMap: { selectedTab = .map }
                )
            }

            Tab("タイムライン", systemImage: "clock", value: .timeline) {
                TimelineView(
                    onFindFriends: { isPresentingFriendAdd = true },
                    onCreateRecord: { selectedTab = .record }
                )
            }

            Tab("プロフィール", systemImage: "person", value: .profile) {
                ProfileView()
            }
            // 受け取ったフレンド申請の件数。0件なら表示されない。
            .badge(friendRequestStore.incomingCount)
        }
        .tint(accentOrange)
        .environment(recordStore)
        .environment(friendRequestStore)
        .task { await recordStore.load() }
        // アプリ起動時（初回のscenePhaseを含む）とフォアグラウンド復帰時に受信申請を取り直す。
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await friendRequestStore.refresh() }
        }
        .sheet(isPresented: $isPresentingFriendAdd) {
            NavigationStack {
                FriendAddView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") { isPresentingFriendAdd = false }
                        }
                    }
            }
            .environment(friendRequestStore)
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthViewModel())
}
