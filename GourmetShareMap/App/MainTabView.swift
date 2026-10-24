//
//  MainTabView.swift
//  GourmetShareMap
//

import SwiftUI

struct MainTabView: View {
    @State private var recordStore = RecordStore()
    private let accentOrange = Color(red: 0.76, green: 0.35, blue: 0.22)

    var body: some View {
        TabView {
            MapView()
                .tabItem {
                    Label("マップ", systemImage: "map")
                }

            RecordCreateView()
                .tabItem {
                    Label("登録", systemImage: "plus")
                }

            ProfileView()
                .tabItem {
                    Label("プロフィール", systemImage: "person")
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
