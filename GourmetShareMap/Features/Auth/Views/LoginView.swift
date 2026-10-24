//
//  LoginView.swift
//  GourmetShareMap
//

import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var currentNonce: String?

    private let backgroundColor = Color(red: 0.984, green: 0.968, blue: 0.937)
    private let accentOrange = Color(red: 0.76, green: 0.35, blue: 0.22)

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 20)

                VStack(spacing: 20) {
                    GourmetMascotView()

                    VStack(spacing: 6) {
                        Text("あなたのご飯を")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.black)
                        Text("覚えん坊")
                            .font(.system(size: 34, weight: .heavy))
                            .foregroundStyle(accentOrange)
                        Text("おいしい記憶を、地図に。")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.black.opacity(0.6))
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 28)

                VStack(spacing: 12) {
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
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if let errorMessage = authViewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 28)
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}
