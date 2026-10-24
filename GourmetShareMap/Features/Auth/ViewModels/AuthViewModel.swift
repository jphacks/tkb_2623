//
//  AuthViewModel.swift
//  GourmetShareMap
//

import AuthenticationServices
import Combine
import Foundation
import Supabase

@MainActor
final class AuthViewModel: ObservableObject {
    @Published private(set) var session: Session?
    @Published var errorMessage: String?
    // TODO: DB設計が決まったら、profilesの登録状況から初回かどうかを判定する。
    @Published private(set) var needsOnboarding = false

    private let client = SupabaseManager.shared.client
    private var authStateTask: Task<Void, Never>?

    init() {
        authStateTask = Task {
            for await (_, session) in client.auth.authStateChanges {
                self.session = session
            }
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String) async {
        guard
            let identityTokenData = credential.identityToken,
            let identityToken = String(data: identityTokenData, encoding: .utf8)
        else {
            errorMessage = "Appleからの認証トークン取得に失敗しました"
            return
        }

        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: identityToken, nonce: rawNonce)
            )
            await upsertProfile(session: session, credential: credential)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        try? await client.auth.signOut()
    }

    // Apple認証は氏名・メールを初回ログイン時にしか返さないため、ここで必ず保存する。
    private func upsertProfile(session: Session, credential: ASAuthorizationAppleIDCredential) async {
        struct ProfileUpsert: Encodable {
            let id: UUID
            let email: String?
            let fullName: String?

            enum CodingKeys: String, CodingKey {
                case id, email
                case fullName = "full_name"
            }
        }

        let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")

        let payload = ProfileUpsert(
            id: session.user.id,
            email: credential.email ?? session.user.email,
            fullName: fullName.isEmpty ? nil : fullName
        )

        do {
            try await client
                .from("profiles")
                .upsert(payload)
                .execute()
        } catch {
            errorMessage = "プロフィール保存に失敗しました: \(error.localizedDescription)"
        }
    }
}
