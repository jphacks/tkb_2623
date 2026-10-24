//
//  LoginView.swift
//  GourmetShareMap
//

import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var currentNonce: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "fork.knife.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .foregroundStyle(.tint)

            Text("GourmetShareMap")
                .font(.largeTitle.bold())

            Spacer()

            SignInWithAppleButton(.signIn) { request in
                let nonce = NonceUtils.randomNonceString()
                currentNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = NonceUtils.sha256(nonce)
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    guard
                        let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                        let nonce = currentNonce
                    else {
                        authViewModel.errorMessage = "Appleの認証情報の取得に失敗しました"
                        return
                    }
                    Task {
                        await authViewModel.signInWithApple(credential: credential, rawNonce: nonce)
                    }
                case .failure(let error):
                    authViewModel.errorMessage = error.localizedDescription
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .padding(.horizontal, 32)

            if let errorMessage = authViewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .padding()
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}
