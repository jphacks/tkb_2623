//
//  MainTabView.swift
//  GourmetShareMap
//

import SwiftUI

struct MainTabView: View {
    @State private var router = AppRouter()

    private let accentOrange = Color(red: 0.76, green: 0.35, blue: 0.22)

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("マップ", systemImage: "map", value: AppTab.map) {
                MapView()
            }

            Tab("登録", systemImage: "plus", value: AppTab.record) {
                RecordView()
            }

            Tab("プロフィール", systemImage: "person", value: AppTab.profile) {
                ProfileView()
            }
        }
        .tint(accentOrange)
        .environment(router)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthViewModel())
}
