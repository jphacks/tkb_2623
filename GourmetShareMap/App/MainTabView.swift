//
//  MainTabView.swift
//  GourmetShareMap
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            MapView()
                .tabItem {
                    Label("マップ", systemImage: "map")
                }

            RecordView()
                .tabItem {
                    Label("登録", systemImage: "plus")
                }

            ProfileView()
                .tabItem {
                    Label("プロフィール", systemImage: "person")
                }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthViewModel())
}
