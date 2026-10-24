//
//  MainTabView.swift
//  GourmetShareMap
//

import SwiftUI

struct MainTabView: View {
    private let accentOrange = Color(red: 0.76, green: 0.35, blue: 0.22)

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
        .tint(accentOrange)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthViewModel())
}
