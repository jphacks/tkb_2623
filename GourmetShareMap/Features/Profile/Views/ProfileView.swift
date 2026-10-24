//
//  ProfileView.swift
//  GourmetShareMap
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text("プロフィール")
            Button("ログアウト") {
                Task { await authViewModel.signOut() }
            }
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthViewModel())
}
