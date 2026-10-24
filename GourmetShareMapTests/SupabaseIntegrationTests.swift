import Foundation
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Xcode Scheme > Test > Arguments > Environment Variables で明示的に有効化する。
// 開発用プロジェクトと、メール確認済みのテスト用アカウントを使用すること。
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RUN_SUPABASE_INTEGRATION_TESTS"] == "1"))
struct SupabaseIntegrationTests {
    private struct Login: Decodable {
        struct User: Decodable { let id: UUID }
        let access_token: String
        let user: User
    }

    private struct Profile: Decodable { let id: UUID }

    private func setting(_ name: String) throws -> String {
        let value = try #require(ProcessInfo.processInfo.environment[name], "Missing \(name)")
        try #require(!value.isEmpty, "Empty \(name)")
        return value
    }

    private func request(
        _ path: String, method: String = "GET", token: String? = nil,
        body: Data? = nil, contentType: String = "application/json"
    ) async throws -> (Data, HTTPURLResponse) {
        let base = try setting("TEST_SUPABASE_URL")
        let url = try #require(URL(string: base + path))
        try #require(url.scheme == "https", "Use an HTTPS development project URL")
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(try setting("TEST_SUPABASE_ANON_KEY"), forHTTPHeaderField: "apikey")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, try #require(response as? HTTPURLResponse))
    }

    private func login(_ account: String) async throws -> Login {
        let body = try JSONSerialization.data(withJSONObject: [
            "email": setting("TEST_USER_\(account)_EMAIL"),
            "password": setting("TEST_USER_\(account)_PASSWORD")
        ])
        let (data, response) = try await request(
            "/auth/v1/token?grant_type=password", method: "POST", body: body
        )
        try #require(response.statusCode == 200, "Test account login failed")
        return try JSONDecoder().decode(Login.self, from: data)
    }

    @Test func ownProfileVisibleAndUnrelatedProfileHidden() async throws {
        let a = try await login("A")
        let b = try await login("B")
        try #require(a.user.id != b.user.id, "A and B must be different users")
        // 現在のschema.sqlはprofiles。移行後はTEST_PROFILE_TABLE=userに設定する。
        let table = ProcessInfo.processInfo.environment["TEST_PROFILE_TABLE"] ?? "profiles"
        try #require(["profiles", "user"].contains(table))
        for (viewer, owner, expected) in [(a, a, 1), (b, b, 1), (a, b, 0), (b, a, 0)] {
            let (data, response) = try await request(
                "/rest/v1/\(table)?select=id&id=eq.\(owner.user.id.uuidString)",
                token: viewer.access_token
            )
            try #require(response.statusCode == 200)
            let rows = try JSONDecoder().decode([Profile].self, from: data)
            #expect(rows.count == expected)
            if expected == 1 { #expect(rows.first?.id == owner.user.id) }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_STORAGE_INTEGRATION_TESTS"] == "1"))
    func ownImageReadableAndUnrelatedUserDenied() async throws {
        let a = try await login("A")
        let b = try await login("B")
        try #require(a.user.id != b.user.id)
        // 1px PNG。テスト自身がアップロードしたファイルだけを削除する。
        let image = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
        for bucket in ["record-images", "profile-images"] {
            let path = "\(a.user.id.uuidString.lowercased())/integration-\(UUID().uuidString).png"
            let object = "/storage/v1/object/\(bucket)/\(path)"
            let (_, uploaded) = try await request(
                object, method: "POST", token: a.access_token, body: image, contentType: "image/png"
            )
            try #require((200..<300).contains(uploaded.statusCode), "Upload failed for \(bucket)")
            do {
                let download = "/storage/v1/object/authenticated/\(bucket)/\(path)"
                let (ownData, ownResponse) = try await request(download, token: a.access_token)
                #expect(ownResponse.statusCode == 200)
                #expect(ownData == image)
                let (_, otherResponse) = try await request(download, token: b.access_token)
                #expect([400, 401, 403, 404].contains(otherResponse.statusCode))
            } catch {
                _ = try? await deleteImage(bucket: bucket, path: path, token: a.access_token)
                throw error
            }
            try await deleteImage(bucket: bucket, path: path, token: a.access_token)
        }
    }

    private func deleteImage(bucket: String, path: String, token: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["prefixes": [path]])
        let (_, response) = try await request(
            "/storage/v1/object/\(bucket)", method: "DELETE", token: token, body: body
        )
        #expect((200..<300).contains(response.statusCode), "Test image cleanup failed")
    }
}
