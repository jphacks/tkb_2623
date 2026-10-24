//
//  MainTabView.swift
//  GourmetShareMap
//

import SwiftUI

struct MainTabView: View {
    enum TabItem: Hashable {
        case map, record, profile
    }

    @State private var recordStore = RecordStore()
    @State private var selectedTab: TabItem = .map
    private let accentOrange = Color(red: 0.76, green: 0.35, blue: 0.22)

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("マップ", systemImage: "map", value: .map) {
                MapView()
            }

            Tab("登録", systemImage: "plus", value: .record) {
                RecordCreateView(isActive: selectedTab == .record)
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
