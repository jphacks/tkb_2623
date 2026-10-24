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
    // TODO: DB設計が決まったら、userテーブルの登録状況から初回かどうかを判定する。
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
            await createUserIfNeeded(session: session, credential: credential)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        try? await client.auth.signOut()
    }

    // 初回ログイン時に user テーブルへ行を作成する。
    // 既に行がある場合は何もしない（2回目以降はAppleが氏名を返さず、上書きすると消えてしまうため）。
    private func createUserIfNeeded(session: Session, credential: ASAuthorizationAppleIDCredential) async {
        struct UserInsert: Encodable {
            let id: UUID
            let email: String?
            let name: String?
        }

        let name = credential.fullName
            .map { PersonNameComponentsFormatter().string(from: $0) }
            .flatMap { $0.isEmpty ? nil : $0 }

        let payload = UserInsert(
            id: session.user.id,
            email: credential.email ?? session.user.email,
            name: name
        )

        do {
            try await client
                .from("user")
                .upsert(payload, onConflict: "id", returning: .minimal, ignoreDuplicates: true)
                .execute()
        } catch {
            errorMessage = "ユーザー情報の保存に失敗しました: \(error.localizedDescription)"
        }
    }
}
