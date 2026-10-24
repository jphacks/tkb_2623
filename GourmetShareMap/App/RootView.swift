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
                MainTabView()
            }
        }
        .environmentObject(authViewModel)
    }
}

#Preview {
    RootView()
}
