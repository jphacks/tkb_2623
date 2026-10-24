//
//  RootView.swift
//  GourmetShareMap
//

import SwiftUI

struct RootView: View {
    @StateObject private var authViewModel = AuthViewModel()

    var body: some View {
        Group {
            if authViewModel.session == nil {
                LoginView()
            } else if authViewModel.needsOnboarding {
                OnboardingView()
            } else {
                MainPlaceholderView()
            }
        }
        .environmentObject(authViewModel)
    }
}

// MainTabViewができたら差し替える。
private struct MainPlaceholderView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text("メイン画面")
            Button("ログアウト") {
                Task { await authViewModel.signOut() }
            }
        }
    }
}

#Preview {
    RootView()
}
