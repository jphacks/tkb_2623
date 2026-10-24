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
    @State private var selectedTab: TabItem = .map
    private let accentOrange = Color(red: 0.76, green: 0.35, blue: 0.22)

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("育てる", systemImage: "sparkles", value: .grow) {
                GrowView()
            }

            Tab("マップ", systemImage: "map", value: .map) {
                MapView()
            }

            Tab("登録", systemImage: "camera", value: .record) {
                RecordCreateView(isActive: selectedTab == .record)
            }

            Tab("タイムライン", systemImage: "clock", value: .timeline) {
                TimelineView(
                    // TODO: フレンド検索画面ができたらそちらへ遷移させる。今はフレンド一覧の入口があるプロフィールへ移る。
                    onFindFriends: { selectedTab = .profile },
                    onCreateRecord: { selectedTab = .record }
                )
            }

            Tab("プロフィール", systemImage: "person", value: .profile) {
                ProfileView()
            }
        }
        .tint(accentOrange)
        .environment(recordStore)
        .task { await recordStore.load() }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthViewModel())
}
